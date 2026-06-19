# APL-EOTF-Corrector

A 2D LUT-based ReShade shader and Python script to help correct APL-dependent HDR EOTF tracking errors.

**Disclaimer:** The code for this project (both the HLSL shader and Python script) was developed with the assistance of Google Gemini.

## Project Philosophy & Community Goal

Many modern monitors force internal tone mapping, panel dimming, or EOTF boosts with no option to disable them. Ideally, displays would feature an HGIG-like mode (behaving like a pure Category 1 monitor) so that users and operating systems could manage the tone mapping pipeline themselves. 

This shader is an attempt to create an artificial HGIG-like mode. By mathematically flattening forced manufacturer EOTF curves, it forces the display to track closer to reference within its physical limits.

### The Community Goal: A Crowdsourced LUT Database
The default LUT in this repository is configured specifically for the Gigabyte MO27Q2, but **this shader can be used with any monitor (including LCDs) to correct both dimming and over-brightening.** 

The primary goal of this project is to build a community-driven database of display-specific LUTs. If you own a colorimeter and choose to profile your display's tracking:
1. Run the sweeps and generate a LUT using the included Python script.
2. Submit a Pull Request with your custom LUT and the raw measurement CSVs.

Over time, this repository can become a shared library of EOTF correction LUTs, allowing people who do not own colorimeters to easily correct their specific monitors.

### Limitations of the Fix
This workaround is not a perfect solution:
* **APL Only:** The shader and script currently only address APL-dependent tracking anomalies. It does not resolve window-size-dependent brightness constraints (such as the display's physical ABL capping full-screen white levels). 
* **Bypassing OS Limits:** Because the shader flattens the display's internal boost, you must bypass the operating system's standard HDR calibration pipeline, which is detailed in the sections below.

## The Included LUT (Gigabyte MO27Q2 QD-OLED)

The default `Gigabyte_MO27Q2_EOTF_Correction_LUT.png` provided in this repository is calibrated specifically for the **Gigabyte MO27Q2** under the following precise conditions:

* **Picture Mode:** HDR Peak 1000
* **Dark Enhance:** OFF
* All other relevant monitor settings are left at their factory defaults.

Using this LUT in other picture modes (such as the HDR mode with APL Stabilize set to High) or on different monitors will not produce accurate tracking.

Out of the box, the MO27Q2 tracks the PQ EOTF curve reasonably well in high APL (average picture level) scenes, but over-brightens the midtones and highlights in low APL (dark) scenes. This LUT attempts to bring the EOTF tracking closer to the PQ reference standard across different APLs. 

If you have a different monitor, or wish to profile a different picture mode, you can use the included Python toolkit to generate a custom LUT using a colorimeter. I used an X-Rite i1 Display Pro to capture my measurements.

## Alternatives and Credits

This shader relies on physical hardware measurements. If you do not own a colorimeter to generate a custom LUT, there are several alternative shaders that use manual data entry to achieve results:

* **[LumaBoost by Valadore](https://github.com/Valadore/LumaBoost)**: A display hardware emulator. You can input your monitor's window brightness specifications (such as those found on review sites like RTINGS) to generate a custom ABL model. It includes features for shadow protection, skin-tone masking, and contrast recovery.
* **[EOTF Boost by MSpeedo](https://github.com/mspeedo/QD-OLED-APL-FIXER) & [ShanSolox](https://github.com/shansolox/QD-OLED-APL-FIXER)**: Shaders featuring 1D APL lookups, BT.2390 Tonemapping, and color-preserving hue limits.
* **[EOTF Boost by DespairArdor](https://github.com/DespairArdor/QD-OLED-APL-FIXER)**: The original ReShade APL tracking shader that inspired this project.

Credit to these developers: the temporal smoothing, BT.2390 tonemapping, and color-preserving math embedded in this shader were adapted directly from the work of MSpeedo and ShanSolox.

## How to Install & Use

1. Install [ReShade](https://reshade.me/) to your game.
2. Download this repository.
3. Place `APL_EOTF_Corrector.fx` into your game's `reshade-shaders\Shaders` folder.
4. Rename `Gigabyte_MO27Q2_EOTF_Correction_LUT.png` to exactly **`EOTF_Correction_LUT.png`**.
5. Place this renamed image into your game's `reshade-shaders\Textures` folder.
6. Launch the game and open the ReShade menu.
7. Enable **APL_EOTF_Corrector**. Make sure it is placed at the **very bottom** of your active effect list so it applies after all other effects.
8. Make sure the `APL Input Mode` in the shader settings matches your game's HDR format (PQ/HDR10 or scRGB). (Note: If using scRGB, leave the `scRGB Signal Reference` at 80 for most games, but adjust it if the midtones look completely washed out).

## System Calibration and the 10,000 Nit Profile Requirement

When the ReShade shader is active, it mathematically flattens the monitor's built-in over-brightening. This forces the display to track the PQ curve closer to reference and behave like a standard hard-clipping monitor. 

Because the monitor is no longer artificially stretching the incoming signal to reach its physical peak, leaving a standard OS-level calibration active will limit your physical highlight headroom. 

For example, if you calibrated the Windows HDR Calibration App using its static 10% window, the OS limits the game engine's maximum signal output to what your display can physically output at that larger window size. Without the monitor's built-in over-brightening to stretch that capped signal back up, your small peak highlights (which are physically capable of reaching much higher luminance levels in dark scenes) will be capped at the lower 10% window limit.

### The Fix: Force a 10,000 Nit Container

To preserve your display's full dynamic range, you must bypass the OS-level clipping limits. This can be done using the [MHC ICC Profile Maker](https://github.com/ttys001/MHC-ICC-Profile-Maker).

Create an ICC profile that matches your monitor's EDID, but set both the **Max** and **Max Full Frame Luminance** to **10,000 nits**.

This configuration tells Windows and your games that the display has unlimited HDR headroom, preventing the OS from pre-compressing or clipping the signal. The raw, untampered HDR signal is then passed directly to the ReShade shader to handle the mathematical corrections.

**Note:** Some modern games rely on the Windows ICC profile to automatically configure their internal HDR settings. For those titles, the in-game peak brightness slider will default to 10,000 nits. You will need to manually adjust the in-game peak brightness slider (or equivalent settings in tools like RenoDX or SpecialK) down to your display's actual physical peak limit. 

Because of this, it is recommended to keep a second, accurately configured profile on hand for games that lack internal HDR calibration menus.

## Generating Your Own LUT (For Calibrators)

A Python script (`process_lut.py`) is included in the `Toolkit` folder. 

**Prerequisites:** You will need Python installed. Install the required dependencies by running:
`pip install numpy pandas scipy imageio`

If you have a colorimeter and HCFR:

1. Use madTPG (included with madVR) or your preferred test pattern generator.
2. Run a sweep of CAPL tests. For the best interpolation results, keep these rules in mind:
   * You **must** run a sweep on a black background to stand in as 0% APL.
   * You **must** run a sweep on a white background to stand in as 100% APL.
   * Run the sweeps with the smallest window size you can (such as a 1% window).
3. Export the sweeps as CSV files named `XX%CAPL.GrayScaleSheet.csv`.
4. Place the CSVs in the same folder as the Python script.
5. Open `process_lut.py` in a text editor and edit the `apl_levels` array to reflect the exact APL percentages you tested.
6. Run the script to generate your custom `EOTF_Correction_LUT.png`. (Example calibration data is provided in the `Data` folder to show the expected format).

---

*This work is licensed under Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International. To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/4.0/*
