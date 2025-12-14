# Photo Organizer Flutter - Features Summary

## Overview
A Flutter-based photo management app with AI-powered tagging using YOLOv8 and CLIP models. The app automatically scans, classifies, and organizes photos with intelligent tag validation.

---

## Main Screens

### 1. **Gallery Screen** (Main)
- **Smart Photo Grid**: Displays all device photos in a responsive grid (1-5 columns, pinch to zoom)
- **AI Tagging**: Automatic classification using YOLO (objects) + CLIP (scenes)
- **Search & Filter**: 
  - Tag-based search with active filter chips
  - Sort by newest/oldest
  - "None" keyword to find untagged photos
- **Photo Management**:
  - Tap to view full-screen
  - Long-press for multi-select mode
  - Bulk tag editing
  - Delete photos
- **Scan Operations**:
  - Manual scan for missing images
  - Force rescan all device images
  - Background scanning with pause/resume
  - Real-time progress indicator
- **Validation System**:
  - Background CLIP validation of existing tags
  - Manual approval workflow with review dialog
  - Individual approve/decline per suggestion
  - Pause/resume/stop validation controls
  - Dynamic threshold adjustment (0.80→0.20)
- **Performance Monitor**:
  - RAM usage tracking
  - Batch processing stats
  - Images per second metrics
- **Unscanned Counter**: Shows number of untagged photos
- **Credits Display**: T-Credit balance indicator

### 2. **Album Screen**
- View organized photo albums
- Album management interface
- Reload functionality

### 3. **Settings Screen**
- **Theme Toggle**: Light/Dark mode with persistent storage
- **Server Configuration**:
  - Server URL management
  - Online/offline status indicator
  - Connection testing
- **Scan Preferences**:
  - WiFi-only scanning option
  - Auto-scan on startup
- **Upload Token**: Configure API authentication

### 4. **Photo Viewer**
- Full-screen photo display
- Hero animation transitions
- Support for local and network images
- Swipe gestures

### 5. **Search Screen**
- Advanced tag search
- Filter combinations
- Search history

### 6. **Pricing Screen**
- Credit purchase options
- Premium features
- Subscription management

### 7. **Explorer Screen**
- File system navigation
- Folder browsing
- Import from specific locations

### 8. **Folder Gallery Screen**
- View photos organized by folder
- Folder-based organization
- Batch operations

### 9. **Organize Progress Screen**
- Real-time organization status
- Progress tracking for bulk operations
- Cancel/pause controls

---

## Key Features

### AI-Powered Classification
- **YOLOv8 Object Detection**: Identifies people, animals, food, and objects
- **CLIP Scene Classification**: Recognizes scenes (scenery, indoors, documents, etc.)
- **Hybrid System**: YOLO authoritative for objects, CLIP enhances with scene tags
- **Smart Validation**: 
  - Never removes YOLO-detected objects (people/animals/food protection)
  - Dynamic threshold search for expected tags
  - Prevents "unknown" tag additions to classified images

### Tag Management
- **Persistent Storage**: Tags saved locally with SharedPreferences
- **Visual Tag Chips**: Color-coded, auto-sized chips on thumbnails
- **Bulk Operations**: 
  - Clear all tags
  - Validate all classifications
  - Batch tag editing
- **Safety Checks**: Prevents empty tag suggestions

### Performance Optimizations
- **Thumbnail Caching**: Stores thumbnails in memory for fast scrolling
- **Lazy Loading**: Loads images as needed
- **Text Width Caching**: Pre-calculates tag chip sizes
- **Batch Processing**: Configurable batch sizes for scanning

### System Integration
- **Edge-to-Edge Display**: Full-screen immersive experience
- **Adaptive System UI**: Status and navigation bars match theme
- **Photo Manager Integration**: Access device photo gallery
- **Permission Handling**: Smart permission requests

### User Experience
- **Glassmorphic UI**: Modern frosted glass effects
- **Gradient Backgrounds**: Dynamic theme-based gradients
- **Smooth Animations**: Hero transitions, progress indicators
- **Responsive Design**: Adapts to screen size and orientation
- **Haptic Feedback**: Touch response
- **Visual Progress**: Real-time scanning and validation indicators

---

## Backend (Python FastAPI Server)

### Core Components
- **FastAPI Server**: RESTful API for image processing
- **YOLOv8 Integration**: Object detection (people, animals, food)
- **CLIP Integration**: Scene classification with dynamic thresholds
- **Hybrid Classification**: Combines YOLO + CLIP intelligently

### API Endpoints
- `/detect_tags`: Single image classification
- `/batch_detect`: Batch image processing
- `/validate`: Tag validation against existing classifications
- Upload management with token authentication

### Features
- **Localhost-only mode**: Safe development
- **Remote access**: WiFi connectivity for physical devices
- **Model selection**: Choose between YOLOv8n/m/x variants
- **Persistent uploads**: Save organized images to target folder
- **Performance monitoring**: Track processing times

---

## Technical Stack

### Frontend
- **Framework**: Flutter (Dart)
- **State Management**: StatefulWidget with setState
- **UI Libraries**: 
  - Material Design 3
  - Google Fonts (Montserrat)
  - ImageFilter for glassmorphism
- **Photo Access**: photo_manager package
- **Storage**: shared_preferences
- **HTTP**: Custom ApiService

### Backend
- **Framework**: FastAPI (Python)
- **ML Models**:
  - Ultralytics YOLOv8 (8.3.236)
  - OpenAI CLIP (clip-vit-base-patch32)
- **Image Processing**: PIL, OpenCV
- **Deep Learning**: PyTorch/ONNX

### Platform Support
- ✅ Android (Primary)
- ✅ Windows (Desktop)
- ✅ Web (Chrome, Edge)
- ⚠️ iOS (Framework support available)

---

## Recent Improvements

### December 2024
- ✅ Edge-to-edge display implementation
- ✅ System UI color matching (transparent status bar, themed navigation)
- ✅ SafeArea removal for full-screen experience
- ✅ Manual approval workflow for validation suggestions
- ✅ YOLO object protection (prevents false unknowns)
- ✅ Dynamic CLIP threshold adjustment
- ✅ Individual approve/decline buttons per suggestion
- ✅ Performance monitoring overlay
- ✅ Pause/resume/stop validation controls

---

## Development Workflow

### Quick Start Commands
```powershell
# Start everything (server + emulator + app)
.\scripts\dev_start_all.ps1

# App only (no server)
.\scripts\dev_start_all.ps1 -NoServer

# Simple emulator launch
.\scripts\run_app_on_emulator_simple.ps1
```

### Hot Reload
- Press `r` in terminal for hot reload
- Press `R` for hot restart
- Press `q` to quit

### Server Management
- Server runs at: `http://192.168.1.198:8000` (WiFi)
- Emulator uses: `http://10.0.2.2:8000` (ADB reverse)
- Auto-discovery available for real devices

---

## Future Enhancements (Not Yet Implemented)

### Performance
- Batch tag loading (currently sequential)
- Deferred unscanned count calculation
- Lazy load tags for visible photos first
- Parallel album loading

### Features
- Custom tag creation
- Album sharing
- Export/Import tag database
- Cloud sync
- Advanced search filters
- Tag suggestions based on history
- Photo editing capabilities

---

**Last Updated**: December 14, 2025
**Version**: Main Branch (Active Development)
**Repository**: Photo-Organizer-Flutter (fominapps-create)
