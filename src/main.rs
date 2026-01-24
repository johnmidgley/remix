use anyhow::{Context, Result};
use axum::{
    extract::{DefaultBodyLimit, Multipart, State},
    http::StatusCode,
    response::{Html, IntoResponse, Json},
    routing::{get, post},
    Router,
};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use clap::Parser;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tower_http::cors::{Any, CorsLayer};
use tower_http::services::ServeDir;
use uuid::Uuid;

use music_tool::{encode_wav_to_bytes, mix_components, process_audio, PcaResult};

#[derive(Parser, Debug)]
#[command(name = "music-tool")]
#[command(about = "Audio PCA decomposition tool with web interface")]
struct Args {
    /// Run in CLI mode (process a file directly)
    #[arg(long)]
    cli: bool,

    /// Input audio file (WAV format) - CLI mode only
    #[arg(short, long)]
    input: Option<PathBuf>,

    /// Number of principal components to extract
    #[arg(short, long, default_value = "3")]
    num_components: usize,

    /// Output directory for component files - CLI mode only
    #[arg(short, long, default_value = ".")]
    output_dir: PathBuf,

    /// FFT window size (power of 2 recommended)
    #[arg(long, default_value = "2048")]
    window_size: usize,

    /// Hop size between windows
    #[arg(long, default_value = "512")]
    hop_size: usize,

    /// Port for web server
    #[arg(short, long, default_value = "3000")]
    port: u16,
}

/// Stored session with processed audio components
#[derive(Clone)]
struct Session {
    result: Arc<PcaResult>,
}

/// Application state
struct AppState {
    sessions: Mutex<HashMap<String, Session>>,
    window_size: usize,
    hop_size: usize,
}

#[derive(Serialize)]
struct ProcessResponse {
    session_id: String,
    num_components: usize,
    eigenvalues: Vec<f64>,
    variance_ratios: Vec<f64>,
    sample_rate: u32,
    /// Base64-encoded WAV for each component
    components: Vec<String>,
}

#[derive(Deserialize)]
struct MixRequest {
    session_id: String,
    volumes: Vec<f64>,
}

#[derive(Serialize)]
struct MixResponse {
    /// Base64-encoded WAV of the mixed audio
    audio: String,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

async fn index() -> Html<&'static str> {
    Html(include_str!("../static/index.html"))
}

async fn process_audio_handler(
    State(state): State<Arc<AppState>>,
    mut multipart: Multipart,
) -> impl IntoResponse {
    let mut audio_data: Option<Vec<u8>> = None;
    let mut num_components: usize = 3;

    while let Some(field) = multipart.next_field().await.ok().flatten() {
        let name = field.name().unwrap_or("").to_string();
        
        match name.as_str() {
            "audio" => {
                if let Ok(data) = field.bytes().await {
                    audio_data = Some(data.to_vec());
                }
            }
            "num_components" => {
                if let Ok(text) = field.text().await {
                    num_components = text.parse::<usize>().unwrap_or(3);
                }
            }
            _ => {}
        }
    }

    let audio_data = match audio_data {
        Some(data) => data,
        None => {
            return (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: "No audio file provided".to_string(),
                }),
            )
                .into_response()
        }
    };

    // Process the audio
    let result = match process_audio(&audio_data, num_components, state.window_size, state.hop_size) {
        Ok(r) => r,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorResponse {
                    error: format!("Processing failed: {}", e),
                }),
            )
                .into_response()
        }
    };

    // Encode each component as base64 WAV
    let mut encoded_components = Vec::new();
    for component in &result.components {
        match encode_wav_to_bytes(component, result.sample_rate) {
            Ok(wav_bytes) => {
                encoded_components.push(BASE64.encode(&wav_bytes));
            }
            Err(e) => {
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorResponse {
                        error: format!("Encoding failed: {}", e),
                    }),
                )
                    .into_response()
            }
        }
    }

    // Create session
    let session_id = Uuid::new_v4().to_string();
    let session = Session {
        result: Arc::new(result),
    };

    {
        let mut sessions = state.sessions.lock().unwrap();
        sessions.insert(session_id.clone(), session);
    }

    let result_ref = {
        let sessions = state.sessions.lock().unwrap();
        sessions.get(&session_id).unwrap().result.clone()
    };

    Json(ProcessResponse {
        session_id,
        num_components: result_ref.components.len(),
        eigenvalues: result_ref.eigenvalues.clone(),
        variance_ratios: result_ref.variance_ratios.clone(),
        sample_rate: result_ref.sample_rate,
        components: encoded_components,
    })
    .into_response()
}

async fn mix_audio_handler(
    State(state): State<Arc<AppState>>,
    Json(request): Json<MixRequest>,
) -> impl IntoResponse {
    let session = {
        let sessions = state.sessions.lock().unwrap();
        sessions.get(&request.session_id).cloned()
    };

    let session = match session {
        Some(s) => s,
        None => {
            return (
                StatusCode::NOT_FOUND,
                Json(ErrorResponse {
                    error: "Session not found".to_string(),
                }),
            )
                .into_response()
        }
    };

    // Mix the components
    let mixed = mix_components(&session.result.components, &request.volumes);

    // Encode as WAV
    match encode_wav_to_bytes(&mixed, session.result.sample_rate) {
        Ok(wav_bytes) => Json(MixResponse {
            audio: BASE64.encode(&wav_bytes),
        })
        .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                error: format!("Encoding failed: {}", e),
            }),
        )
            .into_response(),
    }
}

async fn run_server(args: Args) -> Result<()> {
    let state = Arc::new(AppState {
        sessions: Mutex::new(HashMap::new()),
        window_size: args.window_size,
        hop_size: args.hop_size,
    });

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/", get(index))
        .route("/api/process", post(process_audio_handler))
        .route("/api/mix", post(mix_audio_handler))
        .nest_service("/static", ServeDir::new("static"))
        .layer(DefaultBodyLimit::max(100 * 1024 * 1024)) // 100MB limit
        .layer(cors)
        .with_state(state);

    let addr = format!("0.0.0.0:{}", args.port);
    println!("Starting server at http://localhost:{}", args.port);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

fn run_cli(args: Args) -> Result<()> {
    use hound::{SampleFormat, WavSpec, WavWriter};

    let input = args.input.context("Input file required in CLI mode")?;
    
    println!("Loading audio file: {:?}", input);
    let audio_data = std::fs::read(&input)?;
    
    println!("Processing with {} components...", args.num_components);
    let result = process_audio(&audio_data, args.num_components, args.window_size, args.hop_size)?;
    
    println!("Eigenvalues for top {} components:", result.components.len());
    for (i, (ev, vr)) in result.eigenvalues.iter().zip(result.variance_ratios.iter()).enumerate() {
        println!("  Component {}: eigenvalue = {:.4}, variance = {:.2}%", i + 1, ev, vr);
    }
    
    std::fs::create_dir_all(&args.output_dir)?;
    
    let input_stem = input.file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("audio");
    
    for (i, component) in result.components.iter().enumerate() {
        let output_path = args.output_dir.join(format!("{}_component_{}.wav", input_stem, i + 1));
        println!("Saving: {:?}", output_path);
        
        let spec = WavSpec {
            channels: 1,
            sample_rate: result.sample_rate,
            bits_per_sample: 32,
            sample_format: SampleFormat::Float,
        };
        
        let mut writer = WavWriter::create(&output_path, spec)?;
        for &sample in component {
            writer.write_sample(sample as f32)?;
        }
        writer.finalize()?;
    }
    
    println!("Done! Extracted {} principal components.", result.components.len());
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();
    
    if args.cli {
        run_cli(args)
    } else {
        run_server(args).await
    }
}
