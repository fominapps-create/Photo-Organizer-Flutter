# 3D Character Animation Pipeline

**Goal:** Input prompt + reference image → Output animated video of Filto (or any character)

**Your Hardware:** RTX 3060 Ti (8GB VRAM) - Sufficient for local AI models

---

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────┐
│                    YOUR INPUT                           │
│  ┌─────────────┐  ┌──────────────────────────────────┐  │
│  │ Filto.png   │  │ "Filto waving hello excitedly"   │  │
│  │ (reference) │  │ (motion prompt)                  │  │
│  └─────────────┘  └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ STEP 1: Image → 3D Mesh                                 │
│ Tool: InstantMesh (local) or Tripo AI (API)             │
│ Output: character.glb                                   │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ STEP 2: Auto-Rig                                        │
│ Tool: Mixamo (free API) or AccuRIG (local)              │
│ Output: character_rigged.fbx                            │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ STEP 3: Text → Motion/Animation                         │
│ Tool: MoMask or MDM (local, GPU)                        │
│ Input: "waving hello excitedly"                         │
│ Output: animation.bvh                                   │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ STEP 4: Render to Video                                 │
│ Tool: Blender (headless, CPU)                           │
│ Output: filto_waving.mp4                                │
└─────────────────────────────────────────────────────────┘
```

---

## Option A: ComfyUI (Visual, Easiest)

**What:** Node-based workflow builder with AI integrations

**Pros:**
- Visual drag & drop
- Huge community, pre-made workflows exist
- Easy to modify/experiment

**Cons:**
- Learning curve for node system
- Can be memory-heavy

**Setup time:** 1-2 days

**Install:**
```bash
git clone https://github.com/comfyanonymous/ComfyUI
cd ComfyUI
pip install -r requirements.txt
python main.py
```

---

## Option B: Python Script (More Control)

**What:** Custom Python script chaining local models + APIs

**Pros:**
- Full control
- Can add any UI (Gradio, Streamlit, web)
- Easier to automate/batch

**Cons:**
- More coding required
- Manual integration of each piece

**Setup time:** 2-3 days

**Structure:**
```
filto-animator/
├── main.py              # Main orchestrator
├── image_to_3d.py       # InstantMesh wrapper
├── auto_rig.py          # Mixamo API or AccuRIG
├── text_to_motion.py    # MoMask wrapper
├── render_video.py      # Blender scripting
├── models/              # Downloaded model weights
└── output/              # Generated videos
```

---

## Component Details

### 1. Image → 3D (InstantMesh)

**GitHub:** https://github.com/TencentARC/InstantMesh
**VRAM:** ~6GB
**Quality:** Good for cartoon/stylized characters

```bash
git clone https://github.com/TencentARC/InstantMesh
cd InstantMesh
pip install -r requirements.txt
python run.py --image filto.png --output filto.glb
```

**Alternatives:**
- Wonder3D: https://github.com/xxlong0/Wonder3D
- OpenLRM: https://github.com/3DTopia/OpenLRM
- Tripo AI API: https://tripo3d.ai (free tier, 30/month)

---

### 2. Auto-Rigging

**Mixamo (Recommended - Free API):**
- Website: https://www.mixamo.com
- Upload GLB → Auto-rig → Download FBX
- Can be automated via unofficial API

**AccuRIG (Local alternative):**
- Download: https://actorcore.reallusion.com/auto-rig
- Fully offline

---

### 3. Text → Motion (MoMask)

**GitHub:** https://github.com/EricGuo5513/momask-codes
**VRAM:** ~4GB
**Input:** Text prompt like "person waving hello"
**Output:** BVH/FBX animation file

```bash
git clone https://github.com/EricGuo5513/momask-codes
cd momask-codes
pip install -r requirements.txt
python generate.py --text "waving hello excitedly" --output wave.bvh
```

**Alternatives:**
- MDM: https://github.com/GuyTevet/motion-diffusion-model
- MotionGPT: https://github.com/OpenMotionLab/MotionGPT

---

### 4. Blender Headless Render

**What:** Apply animation to rigged model, render to video

```python
# render_video.py (Blender Python)
import bpy

# Load rigged character
bpy.ops.import_scene.fbx(filepath="filto_rigged.fbx")

# Load animation
bpy.ops.import_anim.bvh(filepath="wave.bvh")

# Set output
bpy.context.scene.render.filepath = "output/filto_waving.mp4"
bpy.context.scene.render.image_settings.file_format = 'FFMPEG'

# Render
bpy.ops.render.render(animation=True)
```

**Run headless:**
```bash
blender --background --python render_video.py
```

---

## Quick-Test Options (No Setup)

Before building, test quality with free tools:

| Tool | Link | Free Limit |
|------|------|------------|
| Viggle AI | discord.gg/viggle | ~10-20/day |
| Pika Labs | discord.gg/pika | ~150/month |
| Kling AI | klingai.com | 66/day |
| Tripo AI | tripo3d.ai | 30 models/month |

---

## Recommended Next Steps

1. **Test Viggle/Pika** with Filto image (5 min) - See if AI quality is acceptable
2. **If good enough:** Use free tiers, no build needed
3. **If not good enough:** Start with InstantMesh locally (test 3D quality)
4. **Then:** Add MoMask for custom animations
5. **Finally:** Chain everything in Python or ComfyUI

---

## Future Enhancements

- [ ] Web UI for non-technical users
- [ ] Batch processing multiple characters
- [ ] Style transfer to match Filto's art style
- [ ] Voice sync / lip sync (Wav2Lip, SadTalker)
- [ ] Background generation (Stable Diffusion)

---

*Created: December 30, 2025*
*Last updated: December 30, 2025*
