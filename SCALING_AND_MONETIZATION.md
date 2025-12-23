# Photo Organizer - Scaling & Monetization Guide

> Summary of architecture decisions, pricing strategy, and implementation roadmap.
> Created: December 22, 2025

---

## Table of Contents
1. [Business Model](#business-model)
2. [Pricing Tiers](#pricing-tiers)
3. [App Navigation & UX Structure](#app-navigation--ux-structure)
4. [Architecture Overview](#architecture-overview)
5. [Cloud vs On-Device Processing](#cloud-vs-on-device-processing)
6. [Cloud Provider Strategy](#cloud-provider-strategy)
7. [AI Models & Capabilities](#ai-models--capabilities)
8. [Semantic Search](#semantic-search)
9. [Face & Pet Recognition](#face--pet-recognition)
10. [Similar Image & Duplicate Detection](#similar-image--duplicate-detection)
11. [Rewarded Ads System](#rewarded-ads-system)
12. [Cost Projections](#cost-projections)
13. [Implementation Phases](#implementation-phases)

---

## Business Model

### Freemium with Rewarded Ads

| Tier | Price | Experience |
|------|-------|------------|
| **Free** | $0 | On-device AI, no ads unless user opts in |
| **Premium** | $2.99/month or $19.99/year | Cloud AI, all features, unlimited |

**Key Principles:**
- No intrusive ads - user chooses to watch rewarded ads for credits
- Premium includes ALL features (no nickel-and-diming)
- Start simple, add complexity only when needed

---

## Pricing Tiers

### Free Tier
- On-device categorization (TFLite YOLO)
- Basic 5 categories: people, animals, food, scenery, documents
- Duplicate detection (pHash - runs locally)
- Optional: Watch rewarded ad for premium feature access

### Premium Tier ($2.99/month)
- Cloud AI processing (YOLO + CLIP)
- Semantic search ("dog playing in snow")
- Face recognition (identify & name people)
- Pet recognition
- Similar image clustering
- All future features included

### Free vs Premium Feature Matrix

| Feature | Free | Premium |
|---------|------|---------|
| **Core** | | |
| Browse & view photos | ✅ | ✅ |
| Share photos | ✅ | ✅ |
| Delete photos | ✅ | ✅ |
| View photo details/metadata | ✅ | ✅ |
| **Organization** | | |
| On-device 5-category tagging | ✅ | ✅ |
| Filter by category | ✅ | ✅ |
| Create manual albums | ✅ | ✅ |
| Favorites/starred photos | ✅ | ✅ |
| View by date/month/year | ✅ | ✅ |
| "Memories" (this day X years ago) | ✅ | ✅ |
| Smart auto-albums by content | ❌ | ✅ |
| **Cleanup (No Cost = No Limit)** | | |
| Screenshot detection | ✅ | ✅ |
| Exact duplicate detection (MD5/pHash) | ✅ | ✅ |
| Bulk delete junk | ✅ Unlimited | ✅ |
| Large file finder | ✅ | ✅ |
| Old screenshots cleaner | ✅ | ✅ |
| Storage stats | ✅ | ✅ |
| **Smart Features (Cloud AI Cost)** | | |
| Semantic search | ❌ (rewarded ad) | ✅ |
| Similar photo detection | ❌ | ✅ |
| Blurry photo detection | ❌ | ✅ |
| Face recognition | ❌ (rewarded ad) | ✅ |
| Pet recognition | ❌ | ✅ |
| AI assistant | ❌ | ✅ |

**Principle:** Only gate features that cost you money (cloud AI). Free features = no limits.

### Rewarded Ads (Free Users)
| Action | Reward |
|--------|--------|
| Watch 1 ad | 3 semantic searches |
| Watch 1 ad | Scan 50 photos with cloud AI |
| Watch 1 ad | Identify 10 faces (not time-based!) |
| Watch 1 ad | Check 1 album for duplicates |

**Design Principles:**
- ❌ Never time-based (prevents "1 ad/day" abuse)
- ✅ Always count-based (runs out, need more ads or premium)
- ✅ Small enough to feel limiting, big enough to show value

**Revenue:** $0.02-0.10 per rewarded ad watched (10-20x more than banner ads)

---

## App Navigation & UX Structure

### Bottom Navigation (3 Tabs + FAB)
```
┌──────────────────────────────────────────────────────────┐
│  ⋮ (3-dot menu - Settings, Help, About)                  │
├──────────────────────────────────────────────────────────┤
│                                                          │
│                     [Content Area]                       │
│                                                          │
│                                              [⭐ FAB]    │
├──────────────────────────────────────────────────────────┤
│     📷              ✨              👤                   │
│   Gallery         Browse          People                 │
└──────────────────────────────────────────────────────────┘
```

| Position | Button | Purpose |
|----------|--------|---------|
| Left | 📷 Gallery | Grid view, albums, category filters |
| **Center** | ✨ **Browse** | Tinder-style photo experience with memories |
| Right | 👤 People | Face recognition groups |
| FAB (floating) | ⭐ | Premium menu + quick actions |

### FAB Menu (When Pressed)
```
                                         ┌─────────────┐
                                         │ ⭐ Premium  │
                                         ├─────────────┤
                                         │ 🔍 Search   │
                                         │ 🧹 Cleanup  │
                                         │ 📊 Stats    │
                                         └─────────────┘
                                              [⭐]
```

| Option | Action |
|--------|--------|
| ⭐ Premium | Opens upgrade/subscription screen |
| 🔍 Search | Semantic search (premium feature) |
| 🧹 Cleanup | Duplicates, screenshots, similar photos |
| 📊 Stats | Storage breakdown, photo stats |

### Browse Mode (Center Tab) - Core Experience
```
┌─────────────────────────────────────────────────────────┐
│  ⋮                                     July 15, 2024   │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │                                                  │   │
│  │                                                  │   │
│  │              [PHOTO FULL VIEW]                  │   │
│  │                                                  │   │
│  │                                                  │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │ 📝 "Beach day with Mom - best sunset ever"      │   │
│  │    #beach #sunset #family                       │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│   ← DELETE     ❤️ FAVORITE      ACTIONS →              │
│                                                         │
├─────────────────────────────────────────────────────────┤
│     📷              ✨              👤         [⭐]     │
└─────────────────────────────────────────────────────────┘
```

### Browse Mode Gestures
| Gesture | Action |
|---------|--------|
| ← Swipe Left | Delete (to trash) |
| → Swipe Right | Open actions panel |
| ↑ Swipe Up | Favorite |
| ↓ Swipe Down | Skip / Next photo |
| Tap photo | Toggle note editor |
| Long Press | Zoom / Full screen |

### Actions Panel (Swipe Right)
```
┌─────────────────────────────────────────┐
│  Actions                            ✕   │
├─────────────────────────────────────────┤
│                                         │
│  📁  Add to Album                       │
│      [Vacation 2024] [Family] [+New]    │
│                                         │
│  📝  Add Note                           │
│      "Write on the back of this photo"  │
│                                         │
│  🏷️  Add Tags                           │
│      #beach #sunset #mom                │
│                                         │
│  📤  Share                              │
│                                         │
│  📍  Edit Location                      │
│                                         │
│  🗓️  Edit Date                          │
│                                         │
└─────────────────────────────────────────┘
```

### Photo Notes Feature (Like Physical Photo Backs)
Allows users to write memories on photos, like writing on the back of physical prints.

```dart
class PhotoNote {
  final String photoId;
  final String note;           // "Beach day with Mom"
  final List<String> tags;     // ["beach", "sunset"]
  final DateTime writtenAt;
}
```

Database schema:
```sql
CREATE TABLE photo_notes (
    photo_id TEXT PRIMARY KEY,
    note TEXT,
    tags TEXT,                 -- JSON array
    written_at TIMESTAMP
);
```

### 3-Dot Menu (Top Left)
```
┌─────────────────────────┐
│  ⚙️  Settings           │
│  ❓  Help & Feedback    │
│  ℹ️  About              │
└─────────────────────────┘
```

### UX Design Principles
| Principle | Implementation |
|-----------|----------------|
| Browse in center | Most used feature = most accessible position |
| Notes on photos | Emotional connection, unique differentiator |
| FAB for premium | Non-intrusive upsell, always visible |
| Actions on right | Natural thumb reach for right-handed users |
| 3 main tabs only | Simple, focused, not overwhelming |
| Gestures in Browse | Gamified, addictive, efficient |

---

## Architecture Overview

### Current Architecture (Development)
```
┌─────────────┐      HTTP       ┌─────────────────┐
│ Flutter App │ ◄─────────────► │ Python Server   │
│ (Phone)     │                 │ (Your PC)       │
│             │                 │ - YOLO + CLIP   │
│ - UI only   │                 │ - SQLite        │
└─────────────┘                 └─────────────────┘
```

### Production Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                      FLUTTER APP                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              TaggingService (Abstract)               │   │
│  └──────────────────┬──────────────────┬───────────────┘   │
│                     │                  │                    │
│         ┌───────────▼───────┐  ┌───────▼────────────┐      │
│         │ LocalTaggingService│  │ CloudTaggingService│      │
│         │ (TFLite - FREE)    │  │ (HTTP - PREMIUM)   │      │
│         └───────────────────┘  └────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### Code Structure
```
lib/
├── services/
│   ├── tagging/
│   │   ├── tagging_service.dart          # Abstract interface
│   │   ├── local_tagging_service.dart    # TFLite (offline/free)
│   │   ├── cloud_tagging_service.dart    # HTTP (online/premium)
│   │   └── tagging_service_factory.dart  # Picks based on user tier
│   └── ...
├── assets/
│   └── models/
│       ├── yolo.tflite                   # 6-25MB
│       └── (optional) clip.tflite        # 50-150MB
```

### Service Interface Pattern
```dart
abstract class TaggingService {
  Future<List<String>> detectTags(String imagePath);
  Future<List<double>> getEmbedding(String imagePath);
}

// Usage - same code works for both:
final service = TaggingServiceFactory.create(user.tier);
final tags = await service.detectTags(photo.path);
```

---

## Cloud vs On-Device Processing

### What Runs Where

| Feature | Free (On-Device) | Premium (Cloud) |
|---------|------------------|-----------------|
| Basic categorization | ✅ TFLite YOLO | ✅ Full YOLO + CLIP |
| Semantic search | ❌ | ✅ CLIP embeddings |
| Face detection | ✅ MediaPipe | ✅ RetinaFace |
| Face recognition | ❌ | ✅ InsightFace |
| Pet recognition | ❌ | ✅ CLIP |
| Duplicate detection | ✅ pHash | ✅ pHash + embeddings |
| OCR | ⚠️ Basic | ✅ Full |

### On-Device Requirements
- YOLO TFLite: 6-25MB model file
- Processing: ~0.5-2 sec/photo (varies by phone)
- Works offline
- No server costs

### Cloud Requirements
- Full YOLO + CLIP models
- Processing: ~0.3 sec/photo (GPU)
- Requires internet
- Server costs apply

---

## Cloud Provider Strategy

### Phase 1: 0-300 Users → Modal (Serverless)
```
Why: Pay only when processing, $0 when idle
Cost: ~$0.001/sec GPU time
Free tier: $30/month credits
Cold start: 2-5 seconds
```

### Phase 2: 300-2000 Users → Still Modal or Switch to Dedicated
```
Evaluate: Is Modal cost > dedicated GPU cost?
Break-even: ~300-500 active users
```

### Phase 3: 2000+ Users → Dedicated GPU (RunPod/Lambda Labs)
```
Why: Cheaper at volume, no cold starts
Cost: $150-500/month for dedicated GPU
Providers: RunPod ($0.20-0.50/hr), Lambda Labs, Vast.ai
```

### Provider Comparison

| Provider | Type | Cost | Best For |
|----------|------|------|----------|
| **Modal** | Serverless | ~$0.001/sec | Starting out (0-500 users) |
| **Replicate** | Serverless | ~$0.005/image | Easy model hosting |
| **RunPod** | Dedicated | $0.20-0.50/hr | Scale (500+ users) |
| **Lambda Labs** | Dedicated | $0.50/hr | Production |
| **Vast.ai** | Spot instances | $0.15-0.50/hr | Cost-sensitive |

### Migration Effort: Modal → Dedicated
- Time: ~30 minutes to 1 hour
- Code changes: Remove Modal wrapper (current code IS the dedicated version)
- Steps:
  1. Spin up RunPod GPU server
  2. Clone repo, install dependencies
  3. Run `python run_server.py --allow-remote`
  4. Update Flutter app URL config

---

## AI Models & Capabilities

### Current Models (All Free/Open-Source)

| Model | Purpose | Size | Accuracy |
|-------|---------|------|----------|
| YOLOv8 | Object detection | 6-170MB | 95%+ |
| CLIP | Image understanding | 600MB | 95% |
| InsightFace | Face recognition | 100MB | 99.7% |
| pHash | Duplicate detection | Algorithm | 99.9% |

### YOLO Detection (80 COCO Classes)
Currently mapping 28 classes to 5 categories:
- **People:** person
- **Animals:** bird, cat, dog, horse, sheep, cow, elephant, bear, zebra, giraffe
- **Food:** banana, apple, sandwich, orange, broccoli, carrot, hot dog, pizza, donut, cake, bottle, wine glass, cup, fork, knife, spoon, bowl
- **Document:** book

Remaining 52 classes (vehicles, furniture, electronics) are searchable but not categorized.

### CLIP Capabilities
- Zero-shot classification (any text prompt)
- Currently using 5-6 prompts, can add unlimited
- Semantic embeddings for search (512-dimensional vectors)
- ~2KB storage per image embedding

---

## Semantic Search

### How It Works
```
Pre-Scan (once per image):
Image → CLIP → 512-dim embedding → Store in database

Search (instant):
"dog playing in snow" → CLIP → 512-dim vector → Compare to stored → Return matches
```

### Storage Requirements
- ~2KB per image (512 floats × 4 bytes)
- 10,000 photos = ~20MB
- 100,000 photos = ~200MB

### Example Searches
| Query | Finds |
|-------|-------|
| "dog playing in snow" | Dogs in snowy scenes |
| "romantic sunset dinner" | Beach dinners, candlelit tables |
| "birthday celebration" | Cakes, candles, party decorations |
| "someone looking sad" | Emotional expressions, gloomy scenes |

### Implementation
- Store embeddings during initial scan
- Use FAISS for fast similarity search at scale
- Endpoint: `/search?q=dog playing in snow`

---

## Face & Pet Recognition

### Face Recognition Pipeline
```
Image
  │
  ├──► Face Detection (RetinaFace/MediaPipe)
  │         └──► Bounding boxes for each face
  │
  ├──► Face Embedding (InsightFace/ArcFace)
  │         └──► 128-512 dim vector per face
  │
  └──► Face Matching
            └──► Compare to known faces → "This is Mom"
```

### Database Schema
```sql
CREATE TABLE people (
    id TEXT PRIMARY KEY,
    name TEXT,                    -- "Mom", "Dad"
    representative_embedding BLOB,
    photo_count INTEGER
);

CREATE TABLE face_occurrences (
    id TEXT PRIMARY KEY,
    photo_id TEXT,
    person_id TEXT,               -- NULL if not identified
    embedding BLOB,
    bounding_box TEXT,
    confidence FLOAT
);
```

### Pet Recognition
- Use CLIP embeddings on cropped pet images
- Cluster similar pets across photos
- User names them: "This is Max"
- Harder than faces (less distinct features)

### Accuracy
| Feature | Model | Accuracy |
|---------|-------|----------|
| Face Detection | RetinaFace | 99.5% |
| Face Recognition | InsightFace | 99.7% |
| Pet Recognition | CLIP | ~85% |

---

## Similar Image & Duplicate Detection

### Types of Similarity

| Type | Method | Use Case |
|------|--------|----------|
| Exact duplicate | MD5 hash | Same file |
| Visual duplicate | pHash | Resized/compressed |
| Near-duplicate | CLIP embeddings | Burst photos |
| Semantically similar | CLIP embeddings | "More like this" |

### Implementation
```python
# Exact duplicates
md5_hash = hashlib.md5(image_bytes).hexdigest()

# Visual duplicates (perceptual hash)
import imagehash
phash = imagehash.phash(Image.open(path))

# Semantic similarity (CLIP + FAISS)
import faiss
index = faiss.IndexFlatIP(512)
index.add(all_embeddings)
similar = index.search(query_embedding, top_k=10)
```

### User Features
- "Clean Up Duplicates" - find and remove copies
- "Burst Photo Picker" - keep best from series
- "Similar Photos" - show more like this

---

## Rewarded Ads System

### Implementation
```dart
class RewardedFeatureService {
  int semanticSearchCredits = 0;
  
  Future<bool> canUseSemanticSearch() async {
    if (user.isPremium) return true;
    if (semanticSearchCredits > 0) return true;
    return false;
  }
  
  Future<void> watchAdForSearches() async {
    final adWatched = await showRewardedAd();
    if (adWatched) {
      semanticSearchCredits += 3;
      saveCredits();
    }
  }
  
  void useSemanticSearch() {
    if (!user.isPremium) {
      semanticSearchCredits--;
    }
  }
}
```

### User Flow
```
Free user tries semantic search
    │
    ▼
┌─────────────────────────────────────┐
│ "Watch a short ad to search"       │
│                                     │
│ [Watch Ad - Get 3 Searches]        │
│                                     │
│ ── or ──                           │
│                                     │
│ [Go Premium - Unlimited]           │
└─────────────────────────────────────┘
```

### Ad Revenue
| Ad Type | Revenue per View |
|---------|------------------|
| Banner | $0.001-0.005 |
| Interstitial | $0.01-0.05 |
| **Rewarded** | **$0.02-0.10** |

---

## AI Chat Assistant (Future Feature)

### Overview
An in-app AI assistant that helps users organize photos through natural language commands.

### Example Commands
| Command | Action |
|---------|--------|
| "Show me photos from last Christmas" | Search by date + semantic "Christmas" |
| "Find all photos of Mom and Dad together" | Face recognition + grouping |
| "Delete all blurry photos" | Quality detection + bulk action |
| "Organize my beach vacation" | Create album from semantic search |
| "Which photos have text in them?" | OCR filter |
| "Free up 2GB of space" | Find duplicates + large files + suggest deletions |

### Implementation Options

| Option | Model | Size/Cost | Speed | Quality | Best For |
|--------|-------|-----------|-------|---------|----------|
| On-Device | Gemma 2B, Phi-3 Mini | 1-4GB | 5-15 sec | Basic | Privacy-focused |
| Cloud API | GPT-4o Mini, Claude Haiku | ~$0.001/convo | 1-3 sec | Excellent | Premium feature |
| Hybrid | Simple→local, Complex→cloud | Mixed | Varies | Good | Balance |

### Cloud LLM Costs
| Model | Cost per 1K tokens | ~Per Conversation |
|-------|-------------------|-------------------|
| GPT-4o Mini | $0.00015 | ~$0.001 |
| Claude Haiku | $0.00025 | ~$0.002 |
| Gemini Flash | $0.000075 | ~$0.0005 |

**1000 conversations = ~$0.50-2.00** (very cheap!)

### Architecture
```dart
class PhotoAssistant {
  Future<AssistantResponse> process(String userMessage) async {
    // 1. Send to LLM with context about available actions
    final intent = await llm.parse(userMessage, availableActions);
    
    // 2. Execute the action
    switch (intent.action) {
      case 'search':
        return await searchPhotos(intent.query, intent.filters);
      case 'delete':
        return await confirmDelete(intent.targets);
      case 'organize':
        return await createAlbum(intent.query);
      case 'cleanup':
        return await findDuplicatesAndSuggest();
    }
  }
}
```

### Flow Diagram
```
┌─────────────────────────────────────────┐
│  💬 "Find birthday photos from 2024"   │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  LLM parses intent:                     │
│  - Action: SEARCH                       │
│  - Semantic: "birthday"                 │
│  - Date filter: 2024                    │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  App executes search + filters          │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  💬 "Found 47 birthday photos! 🎂"     │
│  [Show Photos]                          │
└─────────────────────────────────────────┘
```

### Recommendation
| Priority | Notes |
|----------|-------|
| Phase 5+ | Not essential for MVP |
| Premium only | Good upsell feature |
| Cloud LLM | GPT-4o Mini recommended (cheap + quality) |

---

## Cost Projections

### Processing Cost Per User

| User Type | Photos/Month | Initial Scan | Monthly Cost |
|-----------|--------------|--------------|--------------|
| Light | 100 | 2,000 photos = $0.08 | ~$0.005 |
| Average | 400 | 3,000 photos = $0.12 | ~$0.02 |
| Heavy (moms!) | 1,500 | 5,000 photos = $0.20 | ~$0.07 |
| Extreme | 3,000 | 10,000 photos = $0.40 | ~$0.15 |

**Weighted average: ~$0.05-0.10/user/month after initial scan**

### Profitability by Scale

| Users | Revenue ($2.99/mo) | Cloud Cost | Profit | Margin |
|-------|-------------------|------------|--------|--------|
| 100 | $299 | ~$50 | $249 | 83% |
| 1,000 | $2,990 | ~$200 | $2,790 | 93% |
| 10,000 | $29,900 | ~$600 | $29,300 | 98% |
| 100,000 | $299,000 | ~$3,000 | $296,000 | 99% |

### Break-Even Points
- Modal → Dedicated: ~300-500 users
- Profitable: From user #1 (after initial scan month)

---

## Implementation Phases

### Phase 1: MVP Launch (Current Focus)
- [ ] On-device TFLite YOLO for free tier
- [ ] Keep current Python server for premium
- [ ] Basic categorization (5 categories)
- [ ] App-managed trash/recycle bin (30-day recovery)
- [ ] No ads, no premium yet (validate product)

### Phase 2: Core Differentiators (Easy Wins)
- [ ] **Declutter Mode** - Tinder-style swipe to delete/keep photos
- [ ] **"Why is this here?"** - Show photo source (WhatsApp, screenshot, camera, download)
- [ ] **Mood/Vibe Search** - "happy moments", "aesthetic", "embarrassing" (uses CLIP)
- [ ] **Smart Suggestions Bar** - Contextual actions based on photo content:
  - Copy text (receipts, documents)
  - Save contact (business cards)  
  - Add to calendar (event flyers)
  - Show on map (location photos)
- [ ] Add premium subscription (RevenueCat/in-app purchase)
- [ ] Implement rewarded ads system

### Phase 3: Smart Cleanup Features
- [ ] **Photo Quality Scorer** - Rate photos, detect blur/blinks, suggest best from burst
- [ ] Deploy to Modal (serverless)
- [ ] Add semantic search (CLIP embeddings)
- [ ] Duplicate detection (pHash)
- [ ] Similar image clustering (FAISS)

### Phase 4: Recognition Features
- [ ] Face detection & recognition (InsightFace)
- [ ] Face clustering ("Who is this?")
- [ ] Pet recognition
- [ ] **Find the Original** - Detect screenshots of photos, link to HD original

### Phase 5: Scale Infrastructure
- [ ] Migrate to dedicated GPU (RunPod) when >500 users
- [ ] Add PostgreSQL for multi-user cloud database
- [ ] Per-user authentication (Firebase/Supabase)
- [ ] Background processing queue

### Phase 6: Premium Polish
- [ ] **Smart Story Generator** - Auto-create slideshows from events
- [ ] **Privacy Guardian** - Detect sensitive info (credit cards, IDs, license plates)
- [ ] Memories/auto-albums
- [ ] Advanced search filters
- [ ] Export/backup features

### Phase 7: Advanced AI
- [ ] **AI Chat Assistant** - Natural language photo organization
- [ ] **Before/After Detector** - Find progress photos (fitness, renovation)
- [ ] **Photo DNA** - Track where photos were shared/backed up

---

## Standout Features Summary

### What Makes Us Different From Built-in Galleries

| Feature | Built-in Gallery | Our App |
|---------|------------------|---------|
| Swipe to delete | ❌ | ✅ Declutter Mode |
| Why photo exists | ❌ | ✅ Source detection |
| Mood search | ❌ | ✅ "happy", "aesthetic" |
| Photo quality score | ❌ | ✅ Blur/blink detection |
| Smart suggestions | ❌ | ✅ Copy text, save contact |
| Privacy scan | ❌ | ✅ Detect sensitive info |
| Story generator | Basic | ✅ AI-powered |
| Natural language | ❌ | ✅ AI assistant |

### Feature Difficulty & Impact

| Feature | Difficulty | Wow Factor | Phase |
|---------|------------|------------|-------|
| Declutter Mode (swipe) | ⭐ Easy | 🔥🔥🔥 | 2 |
| "Why is this here?" | ⭐⭐ Medium | 🔥🔥 | 2 |
| Mood/Vibe Search | ⭐⭐ Medium | 🔥🔥🔥 | 2 |
| Smart Suggestions Bar | ⭐⭐ Medium | 🔥🔥🔥 | 2 |
| Photo Quality Scorer | ⭐⭐ Medium | 🔥🔥🔥 | 3 |
| Find the Original | ⭐⭐⭐ Hard | 🔥🔥 | 4 |
| Privacy Guardian | ⭐⭐⭐ Hard | 🔥🔥🔥 | 6 |
| Story Generator | ⭐⭐⭐ Hard | 🔥🔥🔥🔥 | 6 |
| AI Assistant | ⭐⭐⭐ Hard | 🔥🔥🔥 | 7 |
| Before/After Detector | ⭐⭐⭐ Hard | 🔥🔥 | 7 |
| Photo DNA | ⭐⭐⭐⭐ Very Hard | 🔥🔥 | 7 |

---

## Deletion & Trash Strategy

### App-Managed Recycle Bin
```dart
class PendingDeletionService {
  final _db = Database();
  
  /// Mark photos for deletion (moves to app trash)
  Future<void> markForDeletion(List<String> photoIds) async {
    final deleteDate = DateTime.now().add(Duration(days: 30));
    for (final id in photoIds) {
      await _db.insert('pending_deletes', {
        'photo_id': id,
        'delete_after': deleteDate.toIso8601String(),
        'deleted_at': DateTime.now().toIso8601String(),
      });
    }
  }
  
  /// Get photos in trash (for Trash screen)
  Future<List<TrashedPhoto>> getTrash() async {
    return await _db.query('pending_deletes');
  }
  
  /// Restore photo from trash
  Future<void> restore(String photoId) async {
    await _db.delete('pending_deletes', 
      where: 'photo_id = ?', args: [photoId]);
  }
  
  /// Process expired deletions (run on app start)
  Future<void> processExpiredDeletions() async {
    final expired = await _db.query('pending_deletes', 
      where: 'delete_after < ?', 
      args: [DateTime.now().toIso8601String()]
    );
    for (final item in expired) {
      await PhotoManager.editor.deleteWithIds([item['photo_id']]);
      await _db.delete('pending_deletes', 
        where: 'photo_id = ?', args: [item['photo_id']]);
    }
  }
}
```

### Why App-Managed Trash
| Aspect | System Trash | App Trash |
|--------|--------------|-----------|
| Show in our app | ⚠️ Limited/No | ✅ Full control |
| Restore from our app | ⚠️ Limited | ✅ Yes |
| Works all platforms | ⚠️ Inconsistent | ✅ Yes |
| User stays in app | ❌ | ✅ |

---

## Quick Reference

### Pricing
- Free: On-device, rewarded ads for premium features
- Premium: $2.99/month or $19.99/year

### Cloud Providers
- Start: Modal (serverless, pay-per-use)
- Scale: RunPod (dedicated GPU)

### Key Models (All Free)
- YOLO: Object detection
- CLIP: Semantic understanding
- InsightFace: Face recognition
- pHash: Duplicate detection

### Architecture Pattern
```dart
abstract class TaggingService { ... }
class LocalTaggingService implements TaggingService { ... }  // Free
class CloudTaggingService implements TaggingService { ... }  // Premium
```

---

## Notes for Future Implementation

1. **Don't optimize for 100K users before having 100** - start simple
2. **On-device first** - validate app works before adding cloud complexity
3. **Rewarded ads > banner ads** - 10-20x more revenue, better UX
4. **Include all features in premium** - don't nickel-and-dime users
5. **Face recognition sells subscriptions** - use it as the upgrade hook
6. **Modal → Dedicated is easy** - current Python code works on both
7. **Standout features first** - Declutter mode, mood search differentiate from competition
8. **App-managed trash** - Full control over deletion UX

---

*Last updated: December 22, 2025*
