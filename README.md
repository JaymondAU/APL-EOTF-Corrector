# APL-EOTF-Corrector

![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg)
![ReShade 5.9.0+](https://img.shields.io/badge/ReShade-5.9.0%2B-blue.svg)
![Python 3.8+](https://img.shields.io/badge/Python-3.8%2B-yellow.svg)
![OS: Windows](https://img.shields.io/badge/OS-Windows-blue.svg)

A 2D LUT-based ReShade shader and Python toolkit designed to override forced display dimming and correct APL-dependent HDR EOTF tracking errors. Take control of your monitor's tone mapping.

*(Example: Gigabyte MO27Q2 at 10% APL, flattening the factory over-brightened midtones down to reference standard)*
![MO27Q2 10% APL Tracking Correction](Profiles/Gigabyte/MO27Q2/HDR%20Peak%201000/Images/1%25Window10%25APL_BEFORE_AND_AFTER.png)

## Table of Contents
1. [Project Philosophy & Community Goal](#project-philosophy--community-goal)
2. [How It Works](#how-it-works)
3. [Included Profiles](#included-profiles)
4. [How to Install & Use](#how-to-install--use)
5. [System Calibration (10,000 Nit Requirement)](#system-calibration-and-the-10000-nit-profile-requirement)
6. [Generating Your Own LUT (For Calibrators)](#generating-your-own-lut-for-calibrators)
7. [Shoutouts & Standalone Alternatives](#massive-shoutouts--standalone-alternatives)
8. [License](#license)

---

## Project Philosophy & Community Goal

Many modern monitors force internal tone mapping, panel dimming, or EOTF boosts with no option to disable them. Ideally, displays would feature an HGIG-like mode (behaving like a pure Category 1 monitor) so that users and operating systems could manage the tone mapping pipeline themselves. 

This shader is an attempt to create an artificial HGIG-like mode. By mathematically flattening forced manufacturer EOTF curves, it forces the display to track closer to reference within its physical limits.

### The Community Goal: A Crowdsourced LUT Database
The default LUT in this repository is configured specifically for the Gigabyte MO27Q2, but **this shader can be used with any monitor (including LCDs) to correct both dimming and over-brightening.** 

The primary goal of this project is to build a community-driven database of display-specific LUTs. If you own a colorimeter and choose to profile your display's tracking:
1. Run the sweeps and generate a LUT using the included Python script.
2. Structure your files in the `Profiles` directory following the standardized format.
3. Submit a Pull Request to this repository with your custom profile!

**Standard Folder Structure:**
```text
Profiles/
└── [Manufacturer]/
    └── [Model]/
        └── [Picture Mode]/
            ├── EOTF_Correction_LUT.png     <-- Your generated LUT
            ├── HDR Untouched.icc           <-- (Optional) 10k Nit ICC Profile
            ├── README.md                   <-- OSD Settings used for calibration
            ├── Images/                     <-- (Optional) Before/After proofs
            └── Measurements/               
                ├── 0%CAPL.GrayScaleSheet.csv
                ├── 10%CAPL.GrayScaleSheet.csv
                └── ...
```

### Limitations of the Fix
This workaround is not a perfect solution:
* **APL Only:** The shader and script currently only address APL-dependent tracking anomalies. It does not resolve window-size-dependent brightness constraints (such as the display's physical ABL capping full-screen white levels). 
* **Bypassing OS Limits:** Because the shader flattens the display's internal boost, you must bypass the operating system's standard HDR calibration pipeline (detailed below).

---

## How It Works

**The Pipeline:** `Colorimeter Measurements ➔ Python Reverse-Mapping ➔ 16-bit Precision LUT ➔ ReShade MipMap Hardware Sampling ➔ Corrected EOTF Output`

This project consists of two core components working in tandem: a Python script to analyze your monitor's behavior, and a ReShade shader to correct it in real-time.

### 1. The 2D LUT Generation (The Python Script)
Using a colorimeter and calibration software like HCFR, you run EOTF tracking sweeps at various APL levels (e.g., 0%, 5%, 10%, 50%, 100%). 
* **Reverse Mapping:** The script doesn't just subtract the difference; it asks the data: *"What PQ signal do I actually need to send to the monitor to force it to output this exact target luminance?"*
* **Monotonic Interpolation:** It uses a Piecewise Cubic Hermite Interpolating Polynomial (`PchipInterpolator`) to mathematically fill in the gaps between measured patterns. This guarantees the correction curve will never artificially overshoot, dip, or create sudden brightness artifacts.
* **16-Bit Split Packing:** To prevent color banding in HDR, the script calculates an exact 16-bit integer correction value and splits it across the Red and Green channels of a standard 8-bit PNG, ensuring flawless gradient tracking inside ReShade.

### 2. Hardware MipMap APL Calculation (The Shader)
To know how much a monitor is artificially boosting or dimming a scene, the shader must calculate the scene's Average Picture Level (APL).
* **GPU MipMapping:** Instead of computationally expensive loops to average screen pixels, the shader converts the frame to linear light (nits) and uses the GPU's fixed-function texture hardware to instantly average the screen down to a single 1x1 pixel. 
* **Calibration Parity:** This perfectly mirrors the linear light logic that professional calibration software uses to trigger a monitor's physical Auto Brightness Limiter (ABL).

### 3. Real-Time Correction & Temporal Feedback (The Result)
While you play, the shader pulls the exact, pre-calculated reverse-mapped PQ signal from your custom 2D LUT.
* **Color Preservation:** The shader multiplies RGB vectors by a calculated scale factor. This alters brightness while mathematically preserving the exact hue and saturation. An optional limit prevents this scale factor from pushing colors past the monitor's physical peak to prevent discoloration.
* **BT.2390 EETF Tonemapping:** If the corrected signal exceeds the monitor's physical peak brightness, an optional tonemapping pass mathematically compresses the highlights into a smooth "roll-off" to preserve detail instead of hard-clipping.
* **Temporal Feedback Loop:** Altering brightness inherently changes the APL, which could cause infinite flickering. The shader calculates the APL of the *corrected* image and blends it with the previous frame's APL using separate attack and release speeds to ensure smooth transitions.

---

## Included Profiles

The `Profiles` folder contains display-specific EOTF Correction LUTs. **LUTs must be matched to your specific monitor and picture mode.**

The default `EOTF_Correction_LUT.png` is provided for the **Gigabyte MO27Q2**, located in `Profiles/Gigabyte/MO27Q2/HDR Peak 1000/`. It was calibrated under these exact conditions:
* **Picture Mode:** HDR Peak 1000
* **Dark Enhance:** OFF
* Factory defaults for everything else.

*(Example 1: 0% APL Black Background. Flawless tracking up to the 1000 nit hardware clip)*
![MO27Q2 0% APL Tracking Correction](Profiles/Gigabyte/MO27Q2/HDR%20Peak%201000/Images/1%25Window0%25APL_BEFORE_AND_AFTER.png)

*(Example 2: 50% APL. Crushed shadows are accurately lifted, clipping at the ABL's ~300 nit hardware limit)*
![MO27Q2 50% APL Tracking Correction](Profiles/Gigabyte/MO27Q2/HDR%20Peak%201000/Images/1%25Window50%25APL_BEFORE_AND_AFTER.png)

*(Example 3: 100% APL White Background. The entire crushed EOTF curve is pushed upward to track reference standards up to the ~200 nit physical peak)*
![MO27Q2 100% APL Tracking Correction](Profiles/Gigabyte/MO27Q2/HDR%20Peak%201000/Images/1%25Window100%25APL_BEFORE_AND_AFTER.png)

---

## How to Install & Use

1. Install ReShade (v5.9.0 or newer is strongly recommended so the ReShade menu displays correctly in HDR).
2. Download this repository.
3. Place `APL_EOTF_Corrector.fx` into your game's `reshade-shaders\Shaders` folder.
4. Navigate to the `Profiles` folder and find the `EOTF_Correction_LUT.png` for your monitor.
5. Place this image into your game's `reshade-shaders\Textures` folder.
6. Launch the game and open the ReShade menu.
7. Enable **APL_EOTF_Corrector**. Make sure it is placed at the **very bottom** of your active effect list.
8. Make sure the `APL Input Mode` in the shader settings matches your game's HDR format (PQ/HDR10 or scRGB). *(Note: If using scRGB, leave the `scRGB Signal Reference` at 80 for most games, but adjust it if the midtones look completely washed out).*

---

## System Calibration and the 10,000 Nit Profile Requirement

When the ReShade shader mathematically flattens your monitor's built-in over-brightening, the display behaves like a standard hard-clipping monitor. If your game engine relies on a standard Windows OS calibration profile (like an artificially low 400 nit limit created by the Windows HDR Calibration App), the game will artificially clip your physical highlight headroom before the shader can correct it.

*(Example: Using the shader alongside a standard OS profile bottlenecks highlights. Bypassing the OS limit unlocks the monitor's actual 1000-nit physical hardware limit)*
![1000 Nit Highlight Headroom](Profiles/Gigabyte/MO27Q2/HDR%20Peak%201000/Images/1%25Window10%25APL_AFTER.png)

### The Fix: Force a 10,000 Nit Container
To preserve your full dynamic range, you must bypass the OS-level clipping limits. 

1. Check your monitor's profile folder in this repository to see if a `HDR Untouched.icc` is already provided.
2. If not, create an ICC profile matching your monitor's EDID using the [MHC ICC Profile Maker](https://github.com/ttys001/MHC-ICC-Profile-Maker). Set both **Max** and **Max Full Frame Luminance** to **10,000 nits**.

This configuration tells your games and Windows AutoHDR that the display has unlimited HDR headroom. The raw, untampered HDR signal is then passed directly to the ReShade shader to handle the clipping mathematically.

> **Note:** For games that lack internal HDR calibration menus and rely strictly on Windows ICC profiles, your in-game peak brightness slider will now default to 10,000 nits. You will need to manually adjust the in-game peak brightness slider (or use tools like RenoDX/SpecialK) down to your display's actual physical peak limit.

---

## Generating Your Own LUT (For Calibrators)

A Python script (`process_lut.py`) is included in the `Toolkit` folder. 

**Prerequisites:** 
* Python 3.8+
* Install dependencies: `pip install numpy pandas scipy imageio`
* A colorimeter and HCFR (*Note: Use an appropriate spectral correction file/CCSS for your panel technology*).

**Instructions:**
1. Use madTPG (included with madVR) or your preferred test pattern generator.
2. Run a sweep of CAPL tests using the smallest window size possible (e.g., 1%).
   * *Critical:* You **must** run a sweep on a black background (0% APL) and a white background (100% APL) to anchor the interpolator.
3. Export the sweeps as CSV files named `XX%CAPL.GrayScaleSheet.csv` (e.g., `10%CAPL.GrayScaleSheet.csv`).
4. Create your monitor's path: `Profiles/[Manufacturer]/[Model]/[Mode]/Measurements/`.
5. Place your exported CSVs inside the `Measurements` folder.
6. Open your terminal, navigate to the `Toolkit` folder, and run: 
   ```bash
   python process_lut.py --input "../Profiles/[Manufacturer]/[Model]/[Mode]/Measurements" --output "../Profiles/[Manufacturer]/[Model]/[Mode]"
   ```
7. The `EOTF_Correction_LUT.png` will be saved to your profile folder.

---

## Massive Shoutouts & Standalone Alternatives

This project was built on the foundation created by the developers who pioneered APL tracking in ReShade. If you don't have a colorimeter to build hardware-measured LUTs, you should absolutely check out their standalone alternatives:

* **[LumaBoost by Valadore](https://github.com/Valadore/LumaBoost)**: A powerful display hardware emulator. You input your monitor's RTINGS specs to generate a custom ABL model. Packed with shadow protection, skin-tone masking, and contrast recovery.
* **[EOTF Boost by MSpeedo](https://github.com/mspeedo/QD-OLED-APL-FIXER) & [ShanSolox](https://github.com/shansolox/QD-OLED-APL-FIXER)**: Shaders featuring 1D APL lookups, BT.2390 Tonemapping, and color-preserving hue limits. They pioneered mathematical HDR correction in ReShade.
* **[EOTF Boost by DespairArdor](https://github.com/DespairArdor/QD-OLED-APL-FIXER)**: The original ReShade APL tracking shader.

**Credit where it's due:** While this shader introduces hardware-based MipMap calculation and offline Python LUT generation, the foundational APL calculation logic, BT.2390 tonemapping, color-preserving math, and temporal smoothing logic embedded in this shader was directly inspired by and adapted from the open-source work of MSpeedo, ShanSolox, and DespairArdor. Go star their repos.

*Disclaimer: The code for this project was developed with the assistance of Google Gemini.*

---

## License

The primary code and mathematical models for this project are licensed under **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)**. 
[View License](https://creativecommons.org/licenses/by-nc-sa/4.0/)

Portions of the shader code (BT.2390 Tonemapping, Color-Preserving Hue Limits, and temporal smoothing math) are adapted from open-source works by ShanSolox, MSpeedo, and DespairArdor. Those specific portions remain under the **MIT License**. See the header of `APL_EOTF_Corrector.fx` for the full MIT license text and copyright notices.
