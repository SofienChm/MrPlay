# App Store Compliance Checklist

## Before Submission - Verify ALL of these

### ✅ App Description & Metadata
- [ ] App Name: MrPlay
- [ ] Subtitle: "Your Video Hub"
- [ ] Description mentions multi-platform hub, background audio, mini player
- [ ] Keywords include: video hub, background audio, mini player, multi platform
- [ ] Privacy policy URL is accessible
- [ ] Support URL is accessible

### ❌ What to NEVER Include
- [ ] DO NOT mention "ad-free", "no ads", "block ads" anywhere in metadata
- [ ] DO NOT mention "ad blocking" in description or keywords
- [ ] DO NOT screenshot YouTube without ads (if ads appear naturally, fine)
- [ ] DO NOT show "download videos" feature (doesn't exist)
- [ ] DO NOT reference network-level ad blocking

### 🔧 Technical Checks
- [ ] UIBackgroundModes includes "audio" in Info.plist
- [ ] NSAppTransportSecurity allows arbitrary loads (for multi-platform WebView)
- [ ] Bundle identifier matches App Store Connect: com.mrplay.mrplay
- [ ] Version and build number are correct
- [ ] All dependencies are up to date
- [ ] App builds successfully with `flutter build ios --release`
- [ ] No debug flags or debug UI elements visible
- [ ] TestFlight build distributes successfully

### 📱 Functional Testing (TestFlight)
- [ ] Hub screen loads and platforms are tappable
- [ ] WebView loads platform URLs correctly
- [ ] Mini player appears when video plays
- [ ] Background audio continues when app is backgrounded
- [ ] Lock screen controls work (play/pause)
- [ ] Settings screen opens and theme toggle works
- [ ] Favorites can be added/removed
- [ ] Search filters platforms correctly
- [ ] App handles rotation gracefully
- [ ] No crashes on supported iOS versions (iOS 15+)

### 📸 Screenshots
- [ ] Hub screen with platform grid
- [ ] YouTube/WebView loaded naturally
- [ ] Mini player at bottom
- [ ] Settings screen
- [ ] No ad-blocking visible in any screenshot

### 📋 Review Information
- [ ] Demo account credentials prepared
- [ ] Review notes written (app uses WKWebView, background audio)
- [ ] Contact information provided
- [ ] Sign-in instructions for demo account included

## Known Risks (from project map)
1. **YouTube DOM changes** - If YouTube changes their DOM structure, the ad-blocking JS may stop working. Monitor regularly.
2. **Apple rejects for "minimum functionality"** - Emphasize multi-platform hub + native mini player in description. The app has substantial native functionality beyond just WebView.
3. **Background audio rejected** - AVAudioSession must be configured correctly. Test on physical device.
4. **App removed after approval** - Have backup distribution plan (TestFlight, AltStore).

## App Removal Recovery Plan
- [ ] TestFlight distribution for existing users
- [ ] AltStore/sideloading method documented
- [ ] Backup TestFlight build ready
