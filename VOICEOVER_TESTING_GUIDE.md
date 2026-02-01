# VoiceOver Testing Guide for Remix

This document provides a comprehensive guide for testing Remix with VoiceOver to ensure full accessibility compliance for macOS App Store submission.

## Prerequisites

- macOS with VoiceOver enabled (System Settings > Accessibility > VoiceOver)
- Remix application installed
- Test audio files (WAV or MP3)
- Keyboard available for testing

## Quick Reference: VoiceOver Commands

- **Enable/Disable VoiceOver**: ⌘F5
- **VoiceOver modifier (VO)**: Control + Option
- **Navigate**: VO + Arrow Keys
- **Interact with element**: VO + Space
- **Stop speaking**: Control
- **Read item**: VO + F3
- **Rotor menu**: VO + U
- **Adjustable control**: VO + Up/Down Arrow

## Testing Checklist

### 1. Application Launch and Main Window

**Test Steps:**
1. Launch Remix with VoiceOver enabled
2. Verify window title is announced
3. Navigate through main interface elements

**Expected Results:**
- [ ] Window title "Remix" is announced
- [ ] Main content area is accessible
- [ ] Drop zone announces "File drop zone" with hint
- [ ] All controls are navigable with VO + Arrow keys

### 2. File Browser

**Test Steps:**
1. Click sidebar toggle or use VO to navigate to it
2. Navigate through file browser items
3. Test folder navigation and file selection

**Expected Results:**
- [ ] Sidebar toggle announces state (Show/Hide file browser)
- [ ] Folder items announce as "Folder: [name]"
- [ ] Audio files announce as "Audio file: [name]"
- [ ] Quick access locations are labeled (Home, Desktop, Documents, etc.)
- [ ] Selected items are marked as "selected"
- [ ] Double-tap gesture is explained in hints

### 3. Transport Controls

**Test Steps:**
1. Load an audio file
2. Navigate to transport controls
3. Test each transport button

**Expected Results:**
- [ ] Play/Pause button announces current state
- [ ] Stop button is labeled "Stop"
- [ ] Go to beginning button is labeled correctly
- [ ] Loop button announces state (Enable/Disable loop)
- [ ] Space bar shortcut is mentioned in play/pause hint
- [ ] Time display announces current and total time

### 4. Timeline and Waveform

**Test Steps:**
1. Navigate to timeline area
2. Test seeking with keyboard
3. Test loop region creation

**Expected Results:**
- [ ] Timeline announces as "Timeline and waveform"
- [ ] Current playhead position is announced
- [ ] Loop region existence and boundaries are announced
- [ ] Interaction hints explain click to seek and drag to loop
- [ ] Left/Right arrow keys seek backward/forward 5 seconds
- [ ] Escape key clears loop region

### 5. Mixer Channel Strips

**Test Steps:**
1. After analysis, navigate to mixer area
2. Test each channel strip
3. Verify all controls per stem

**Expected Results:**

#### Per Channel (Drums, Bass, Vocals, Guitar, Keys, Other):

**Faders:**
- [ ] Announces "[Stem Name] volume fader"
- [ ] Reports current value in decibels
- [ ] VO + Up/Down arrows adjust value
- [ ] Adjustable action increments/decrements by 5%
- [ ] Tooltip shows on hover

**Pan Knobs:**
- [ ] Announces "[Stem Name] pan control"
- [ ] Reports position (Center, X% Left, X% Right)
- [ ] VO + Up/Down arrows adjust pan
- [ ] Hint explains double-tap to center
- [ ] Tooltip shows on hover

**Meters:**
- [ ] Announces "[Stem Name] level meter"
- [ ] Reports level percentage and description (Low, Medium, High)
- [ ] Updates dynamically during playback

**Solo/Mute Buttons:**
- [ ] Solo button announces "Solo [Stem Name]"
- [ ] Mute button announces "Mute [Stem Name]"
- [ ] Current state (active/inactive) is conveyed
- [ ] "Selected" trait added when active
- [ ] Hints explain toggle behavior
- [ ] Tooltips show on hover

### 6. Toolbar Controls

**Test Steps:**
1. Navigate to toolbar area
2. Test each toolbar control

**Expected Results:**
- [ ] Playback speed picker announces "Playback speed" and current value
- [ ] Pitch picker announces "Pitch shift" and semitone value
- [ ] Bounce button labeled "Bounce mix"
- [ ] EQ button labeled "Open equalizer"
- [ ] All disabled states are announced
- [ ] Keyboard shortcuts mentioned in tooltips

### 7. Menu Bar

**Test Steps:**
1. Navigate menu bar with VoiceOver
2. Test each menu and menu item
3. Verify keyboard shortcuts are announced

**Expected Results:**
- [ ] File menu items are all accessible
- [ ] Transport menu items announce correctly
- [ ] Help menu is accessible
- [ ] About menu item is present
- [ ] Preferences menu item (⌘,) is accessible
- [ ] Keyboard shortcuts are announced with menu items

### 8. Sheets and Dialogs

**Test Steps:**
1. Open Help sheet (⌘?)
2. Open About sheet
3. Open Preferences sheet (⌘,)
4. Test error dialogs if applicable

**Expected Results:**

**Help Sheet:**
- [ ] Sheet title "Remix Help" is announced
- [ ] Content is navigable and readable
- [ ] Close button is accessible
- [ ] Escape key closes sheet
- [ ] Keyboard shortcuts table is accessible

**About Sheet:**
- [ ] Title "About Remix" is announced
- [ ] Version information is readable
- [ ] License text is accessible and selectable
- [ ] Close button works with Escape

**Preferences:**
- [ ] Tab navigation between sections works
- [ ] All form controls are labeled
- [ ] Radio buttons announce selection
- [ ] Toggles announce state
- [ ] Escape closes preferences

### 9. Context Menus

**Test Steps:**
1. Right-click (or VO + Shift + M) on various elements
2. Navigate context menu items
3. Test menu actions

**Expected Results:**

**File Browser:**
- [ ] Context menu appears for files/folders
- [ ] "Reveal in Finder" option is accessible
- [ ] "Load File" option for audio files
- [ ] "Get Info" option is accessible

**Channel Strips:**
- [ ] Right-click on channel strip shows menu
- [ ] "Reset Fader" option is accessible
- [ ] "Reset Pan" option is accessible
- [ ] "Reset All" option is accessible
- [ ] "Solo/Mute" toggle options are accessible

**Timeline:**
- [ ] Context menu on timeline is accessible
- [ ] "Clear Loop Region" available when region exists
- [ ] "Go to Beginning/End" options work

### 10. Keyboard-Only Navigation

**Test Steps:**
1. Disable mouse/trackpad
2. Navigate entire app using only keyboard
3. Verify all functionality is accessible

**Expected Results:**
- [ ] Tab key navigates through all interactive elements
- [ ] Space bar activates buttons
- [ ] Arrow keys navigate lists and adjust sliders
- [ ] Escape dismisses sheets and clears selections
- [ ] All menu commands have keyboard shortcuts
- [ ] Custom keyboard shortcuts work (Space, ⌘B, ⌘E, ⌘R, etc.)

### 11. Full Screen Mode

**Test Steps:**
1. Enter full screen (⌃⌘F)
2. Navigate with VoiceOver
3. Exit full screen

**Expected Results:**
- [ ] Full screen transition is smooth
- [ ] All controls remain accessible in full screen
- [ ] VoiceOver continues to work correctly
- [ ] Full screen exit is accessible

### 12. Quit Behavior

**Test Steps:**
1. Start audio playback
2. Attempt to quit application (⌘Q)
3. Test dialog response

**Expected Results:**
- [ ] Warning dialog appears if audio is playing
- [ ] Dialog announces "Audio is Playing"
- [ ] Quit and Cancel buttons are accessible
- [ ] Focus automatically on buttons
- [ ] Escape cancels quit

## Common Issues to Check

### Unlabeled Controls
- All buttons should have meaningful labels
- Icons alone are not sufficient
- Generic labels like "Button" indicate missing accessibility

### Incorrect Traits
- Buttons should have `.isButton` trait
- Selected items should have `.isSelected` trait
- Adjustable controls should support increment/decrement

### Missing Hints
- Complex controls should have hints explaining usage
- Hints should be concise (one sentence)
- Don't repeat the label in the hint

### Navigation Issues
- Controls should be in logical order
- Tab order should match visual layout
- No "black holes" where navigation gets stuck

### Dynamic Content
- Changes in state should be announced
- Meter levels should update
- Play/pause state changes should be announced

## Testing with Different VoiceOver Settings

### High-Speed VoiceOver
1. Increase VoiceOver speech rate to maximum
2. Verify all labels are still understandable
3. Check that rapid navigation doesn't miss elements

### Reduced Motion
1. Enable "Reduce Motion" in Accessibility settings
2. Verify animations don't interfere with VoiceOver
3. Check that functionality still works

### High Contrast Mode
1. Enable "Increase Contrast" setting
2. Verify all text remains readable
3. Check that focus indicators are visible

## Reporting Issues

When documenting issues, include:
1. **Element affected**: Specific control or view
2. **Expected behavior**: What should be announced
3. **Actual behavior**: What VoiceOver actually says
4. **Steps to reproduce**: Exact navigation path
5. **VoiceOver settings**: Any non-default settings in use

## Sign-Off Checklist

Before submitting to App Store:
- [ ] All sections above tested and passing
- [ ] No unlabeled interactive elements
- [ ] All hints are helpful and accurate
- [ ] Keyboard navigation is complete
- [ ] Context menus are accessible
- [ ] Sheets and dialogs work with VoiceOver
- [ ] No VoiceOver-breaking bugs
- [ ] Documentation updated with any known limitations

## Additional Resources

- [Apple VoiceOver User Guide](https://support.apple.com/guide/voiceover/welcome/mac)
- [Apple Accessibility Programming Guide](https://developer.apple.com/accessibility/)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [macOS Human Interface Guidelines - Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

## Notes

- Testing should be performed by someone familiar with VoiceOver
- Ideally, have a blind or low-vision user test the app
- Document any workarounds needed for complex controls
- Update this guide as new features are added

---

**Last Updated**: 2026-02-01
**Tested By**: [To be completed during testing]
**Version**: 1.0
**Status**: Ready for Testing
