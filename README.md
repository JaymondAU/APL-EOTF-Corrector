# APL-EOTF-Corrector

A 2D LUT-based ReShade shader and Python toolkit designed to override forced display dimming and correct APL-dependent HDR EOTF tracking errors. Take control of your monitor's tone mapping.

## Project Philosophy & Community Goal

Many modern monitors force internal tone mapping, panel dimming, or EOTF boosts with no option to disable them. Ideally, displays would feature an HGIG-like mode (behaving like a pure Category 1 monitor) so that users and operating systems could manage the tone mapping pipeline themselves. 

This shader is an attempt to create an artificial HGIG-like mode. By mathematically flattening forced manufacturer EOTF curves, it forces the display to track closer to reference within its physical limits.

### The Community Goal: A Crowdsourced LUT Database
The default LUT in this repository is configured specifically for the Gigabyte MO27Q2, but **this shader can be used with any monitor (including LCDs) to correct both dimming and over-brightening.** 

The primary goal of this project is to build a community-driven database of display-specific LUTs. If you own a colorimeter and choose to profile your display's tracking:
1. Run the sweeps and generate a LUT using the included Python script.
2. Structure your files in the `Profiles` directory following this format: `Profiles/[Manufacturer]/[Model]/[Mode]/`. 
3. Place your raw measurement CSVs inside a `Measurements/` subfolder, and the final generated `EOTF_Correction_LUT.png` in the root of your mode folder. Include a `README.md` detailing the required monitor OSD settings.
4. Submit a Pull Request to this repository with your custom profile.

Over time, this repository can become a shared library of EOTF correction LUTs, allowing people who do not own colorimeters to easily correct their specific monitors.

### Limitations of the Fix
This workaround is not a perfect solution:
* **APL Only:** The shader and script currently only address APL-dependent tracking anomalies. It does not resolve window-size-dependent brightness constraints (such as the display's physical ABL capping full-screen white levels). 
* **Bypassing OS Limits:** Because the shader flattens the display's internal boost, you must bypass the operating system's standard HDR calibration pipeline, which is detailed in the sections below.

## How It Works

This project consists of two core components working in tandem: a Python script to analyze your monitor's behavior, and a ReShade shader to correct it in real-time.

1. **The 2D LUT Generation (The Python Script)**
   Using a colorimeter and calibration software like HCFR, you run EOTF tracking sweeps at various APL levels (e.g., 0%, 5%, 10%, 50%, 100%). You feed these raw CSV measurements into the included Python script. 
   The script does not simply subtract the difference; it performs a **reverse mapping**. For every possible target luminance (nits) at every APL level, it asks the data: *"What PQ signal do I actually need to send to the monitor to force it to output this exact target luminance?"* 
   Because you can only manually measure a limited number of test patterns, the script uses a Piecewise Cubic Hermite Interpolating Polynomial (`PchipInterpolator`) to mathematically fill in the gaps. It interpolates smoothly across the luminance axis, and then vertically across the APL axis. This specific interpolation method is crucial because it strictly preserves monotonicity—meaning it guarantees the generated correction curve will never artificially overshoot, dip, or create sudden brightness artifacts.
   Finally, to prevent the notorious color banding that plagues standard 8-bit LUTs in HDR, the script packs the data using a **16-bit precision split**. It calculates the exact 16-bit integer correction value and splits it across the Red and Green channels of a standard 8-bit PNG, ensuring flawless gradient tracking inside ReShade.

2. **Hardware MipMap APL Calculation (The Shader)**
   To know how much a monitor is artificially boosting or dimming a scene, the shader must first understand the scene's overall brightness, known as the Average Picture Level (APL).
   Instead of using computationally expensive loops to average the screen pixels, the shader leverages GPU hardware MipMapping. It converts the frame's luminance into a linear light scale (absolute physical nits), and uses the GPU's texture sampling hardware to instantly average the entire screen down to a single 1x1 pixel. This perfectly mirrors the mathematical linear light logic that professional calibration software uses to trigger a monitor's physical Auto Brightness Limiter (ABL), ensuring the shader and your monitor's power supply are speaking the exact same mathematical language.

3. **Real-Time Correction, Color Preservation, & Temporal Feedback (The Result)**
   While you play a game, the shader calculates the linear APL and uses it alongside the game's intended pixel brightness to pull the exact, pre-calculated reverse-mapped PQ signal from the 2D LUT (unpacking the 16-bit Red/Green channels back into a highly precise float).
   Instead of blindly replacing the color, the shader converts the pixel to Linear RGB and calculates a single **luminance scale factor**. By multiplying the RGB vectors by this scale, it alters the brightness while mathematically preserving the exact hue and saturation of the original color. It also features an optional **Color Preservation** limit that prevents this scale factor from pushing any individual color channel past the monitor's physical peak brightness, preventing highlight discoloration.
   If the corrected signal still exceeds the monitor's physical peak brightness limit, an optional **BT.2390 EETF Tonemapping** pass can be applied. Instead of hard-clipping and destroying highlight detail (like the texture of clouds), this mathematically compresses the highlights into a smooth "roll-off" to preserve those details. *(Note: Theoretically, both Color Preservation and BT.2390 Tonemapping are unnecessary for preventing physical monitor clipping, because the Python script inherently hard-caps the 2D LUT to the maximum brightness your monitor was measured to be able to output. They are simply provided as options if you prefer a smooth roll-off over a hard clip.)*
   Finally, because altering the brightness of the pixels inherently changes the APL of the screen (which could cause an infinite feedback loop of flickering), the shader implements a **temporal feedback loop**. It calculates the APL of the *corrected* image and blends it with the previous frame's APL using a framerate-independent exponential moving average. Separate attack and release speeds smooth out APL transitions and ensure the correction always reaches a steady state without flickering or hunting.

## Included Profiles

The `Profiles` folder contains display-specific EOTF Correction LUTs, separated by manufacturer, model, and picture mode. 

For example, the default `EOTF_Correction_LUT.png` provided for the **Gigabyte MO27Q2** is located in `Profiles/Gigabyte/MO27Q2/HDR Peak 1000/`. It was calibrated under the following precise conditions:

* **Picture Mode:** HDR Peak 1000
* **Dark Enhance:** OFF
* All other relevant monitor settings are left at their factory defaults.

Using a LUT designed for one picture mode (such as HDR Peak 1000) while the monitor is set to a different mode (such as HDR+APL High), or using it on a completely different monitor, will not produce accurate tracking.

Out of the box, the MO27Q2 tracks the PQ EOTF curve reasonably well in high APL (average picture level) scenes, but over-brightens the midtones and highlights in low APL (dark) scenes. This LUT attempts to bring the EOTF tracking closer to the PQ reference standard across different APLs. 

*(Example 1 for the MO27Q2: 0% APL Black Background, showing flawless tracking across the entire brightness curve until reaching the physical 1000 nit hardware clip)*
![MO27Q2 0% APL Tracking Correction](Profiles/Gigabyte/MO27Q2/HDR%20Peak%201000/Images/1%25Window0%25APL_BEFORE_AND_AFTER.png)

*(Example 2 for the MO27Q2: 10% APL, demonstrating the massive flattening of the factory over-brightened midtones down to reference standard)*
![MO27Q2 10% APL Tracking Correction](Profiles/Gigabyte/MO27Q2/HDR%20Peak%201000/Images/1%25Window10%25APL_BEFORE_AND_AFTER.png)

*(Example 3 for the MO27Q2: 50% APL, showing crushed shadows being accurately lifted and highlights clipping at the ABL's ~300 nit hardware limit)*
![MO27Q2 50% APL Tracking Correction](Profiles/Gigabyte/MO27Q2/HDR%20Peak%201000/Images/1%25Window50%25APL_BEFORE_AND_AFTER.png)

*(Example 4 for the MO27Q2: 100% APL White Background, showing the entire crushed EOTF curve being pushed upward to perfectly track reference standards up to the ~200 nit physical peak)*
![MO27Q2 100% APL Tracking Correction](Profiles/Gigabyte/MO27Q2/HDR%20Peak%201000/Images/1%25Window100%25APL_BEFORE_AND_AFTER.png)

If you have a different monitor, or wish to profile a different picture mode, you can use the included Python toolkit to generate a custom LUT using a colorimeter, and submit it to the repository!

## Massive Shoutouts & Standalone Alternatives

This project was built on the foundation created by the developers who pioneered APL tracking in ReShade. All four of these individuals laid the groundwork that inspired this approach. 

If you don't have a colorimeter to build hardware-measured LUTs, you should check out their work. They let you dial in the corrections manually and achieve great results:

* **[LumaBoost by Valadore](https://github.com/Valadore/LumaBoost)**: A powerful display hardware emulator. You can input your monitor's specific window brightness specs (like the ones from RTINGS) to generate a custom ABL model. It's packed with features for shadow protection, skin-tone masking, and contrast recovery.
* **[EOTF Boost by MSpeedo](https://github.com/mspeedo/QD-OLED-APL-FIXER) & [ShanSolox](https://github.com/shansolox/QD-OLED-APL-FIXER)**: Shaders featuring 1D APL lookups, BT.2390 Tonemapping, and color-preserving hue limits. They pioneered mathematical HDR correction in ReShade.
* **[EOTF Boost by DespairArdor](https://github.com/DespairArdor/QD-OLED-APL-FIXER)**: The original ReShade APL tracking shader.

**Credit where it's due:** While this shader uses a different hardware-based MipMap approach, the foundational APL calculation logic, as well as the temporal smoothing, BT.2390 tonemapping, and color-preserving math embedded in this shader, was directly inspired by and adapted from the open-source work of MSpeedo, ShanSolox, and DespairArdor. Go star their repos.

## How to Install & Use

1. Install [ReShade](https://reshade.me/) to your game.
2. Download this repository.
3. Place `APL_EOTF_Corrector.fx` into your game's `reshade-shaders\Shaders` folder.
4. Navigate to the `Profiles` folder and find the specific `EOTF_Correction_LUT.png` generated for your exact monitor and picture mode.
5. Place this image into your game's `reshade-shaders\Textures` folder.
6. Launch the game and open the ReShade menu.
7. Enable **APL_EOTF_Corrector**. Make sure it is placed at the **very bottom** of your active effect list so it applies after all other effects.
8. Make sure the `APL Input Mode` in the shader settings matches your game's HDR format (PQ/HDR10 or scRGB). (Note: If using scRGB, leave the `scRGB Signal Reference` at 80 for most games, but adjust it if the midtones look completely washed out).

## System Calibration and the 10,000 Nit Profile Requirement

When the ReShade shader is active, it mathematically flattens the monitor's built-in over-brightening. This forces the display to track the PQ curve closer to reference and behave like a standard hard-clipping monitor. 

Because the monitor is no longer artificially stretching the incoming signal to reach its physical peak, leaving a standard OS-level calibration active will bottleneck your physical highlight headroom. 

Out of the box, modern monitors handle OS HDR signals in different ways. Some monitors force you to set a low OS clip point (e.g., ~380 nits for the MO27Q2) and then artificially stretch that signal up to reach their physical peak (such as ~1050 nits for a 1% highlight). Other monitors may allow a high OS clip point (like 1000 nits) but dynamically compress that signal down to whatever their physical ABL limit is (e.g., ~400-600 nits in a 10% window). 

However, when the shader is active, these artificial stretches and compressions are mathematically flattened. If your game engine relies on the OS calibration profile to set its peak brightness (such as an artificially low 380 nit limit), the game will never render highlights brighter than that limit, artificially clipping your physical highlight headroom.

### The Fix: Force a 10,000 Nit Container

*(Example for the MO27Q2: Once the display's artificial over-brightening is mathematically flattened, small highlights at low APLs can accurately track up to 1000 nits. However, if your game relies on a standard OS calibration profile with a low peak luminance (like ~380 nits based on the HDR Calibration App), the game engine will limit its maximum output, artificially clipping your highlights before they even reach the shader.)*
![1000 Nit Highlight Headroom](Profiles/Gigabyte/MO27Q2/HDR%20Peak%201000/Images/1%25Window10%25APL_AFTER.png)

To preserve your display's full dynamic range, you must bypass the OS-level clipping limits. 

Check your specific monitor's profile folder in this repository to see if a pre-made 10,000 nit ICC profile (such as `HDR Untouched.icc`) is already provided for you to install.

If not, you can create this profile using the [MHC ICC Profile Maker](https://github.com/ttys001/MHC-ICC-Profile-Maker). Create an ICC profile that matches your monitor's EDID, but set both the **Max** and **Max Full Frame Luminance** to **10,000 nits**.

This configuration tells your games and AutoHDR that the display has unlimited HDR headroom, preventing them from pre-compressing or clipping the signal. The raw, untampered HDR signal is then passed directly to the ReShade shader to handle the mathematical corrections.

**Note:** Some modern games rely on the Windows ICC profile to automatically configure their internal HDR settings. For those titles, the in-game peak brightness slider will default to 10,000 nits. You will need to manually adjust the in-game peak brightness slider (or equivalent settings in tools like RenoDX or SpecialK) down to your display's actual physical peak limit. 

Because of this, it is recommended to keep a second, accurately configured profile on hand for games that lack internal HDR calibration menus.

## Generating Your Own LUT (For Calibrators)

A Python script (`process_lut.py`) is included in the `Toolkit` folder. 

**Prerequisites:** You will need Python installed. Install the required dependencies by running:
`pip install numpy pandas scipy imageio`

If you have a colorimeter and HCFR:

* **A Note on Spectral Corrections (CCSS):** For the highest accuracy, ensure you are using an appropriate spectral correction file (like a CCSS) in HCFR for your specific panel technology (e.g., QD-OLED, WOLED), assuming your colorimeter requires one.

1. Use madTPG (included with madVR) or your preferred test pattern generator.
2. Run a sweep of CAPL tests. For the best interpolation results, keep these rules in mind:
   * You **must** run a sweep on a black background to stand in as 0% APL.
   * You **must** run a sweep on a white background to stand in as 100% APL.
   * Run the sweeps with the smallest window size you can (such as a 1% window).
3. Export the sweeps as CSV files named `XX%CAPL.GrayScaleSheet.csv` (e.g., `0%CAPL.GrayScaleSheet.csv`).
4. Create your monitor's profile folder path: `Profiles/[Manufacturer]/[Model]/[Mode]/Measurements/`.
5. Place your exported CSVs inside that `Measurements` folder.
6. Open your terminal or command prompt and navigate to the `Toolkit` folder.
7. Run the script, pointing it to your measurements and desired output folder: 
   `python process_lut.py --input "../Profiles/[Manufacturer]/[Model]/[Mode]/Measurements" --output "../Profiles/[Manufacturer]/[Model]/[Mode]"`
   (The `EOTF_Correction_LUT.png` will be saved automatically to your profile folder).

---

**Disclaimer:** The code for this project (both the HLSL shader and Python script) was developed with the assistance of Google Gemini.

## License

The primary code and mathematical models for this project are licensed under **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)**. 
[View License](https://creativecommons.org/licenses/by-nc-sa/4.0/)

Portions of the shader code (BT.2390 Tonemapping, Color-Preserving Hue Limits, and temporal smoothing math) are adapted from open-source works by ShanSolox, MSpeedo, and DespairArdor. Those specific portions remain under the **MIT License**. See the header of `APL_EOTF_Corrector.fx` for the full MIT license text and copyright notices.
