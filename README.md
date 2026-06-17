# APL-EOTF-Corrector

A 2D LUT-based ReShade shader and Python script to help correct APL-dependent HDR EOTF tracking errors.

**Disclaimer:** The code for this project (both the HLSL shader and Python script) was heavily vibe coded with Google Gemini.

## The Included LUT (Gigabyte MO27Q2 QD-OLED)

The `Gigabyte_MO27Q2_EOTF_Correction_LUT.png` included in this repository by default was calibrated specifically for my **Gigabyte MO27Q2 in its Peak 1000 mode**.

Out of the box, this monitor tracks the PQ EOTF curve fairly accurately in high APL (bright) scenes, but aggressively over-brightens the midtones and highlights in low APL (dark) scenes. This LUT tries to restore accurate EOTF tracking across all APLs.

If you are using a different monitor, this specific LUT probably won't look correct, but you can use the included Python toolkit to generate one for your own display if you have a colorimeter. I used an X-Rite i1 Display Pro that I bought used for $220 AUD.

## How to Install & Use

1. Install [ReShade](https://reshade.me/) to your game.
2. Download this repository.
3. Place `APL_EOTF_Corrector.fx` into your game's `reshade-shaders\Shaders` folder.
4. Rename `Gigabyte_MO27Q2_EOTF_Correction_LUT.png` to exactly **`EOTF_Correction_LUT.png`**.
5. Place this renamed image into your game's `reshade-shaders\Textures` folder.
6. Launch the game and open the ReShade menu.
7. Enable **APL_EOTF_Corrector**. Make sure the `APL Input Mode` in the shader settings matches your game's HDR format (PQ/HDR10 or scRGB).

## A Warning About the Windows HDR Calibration App

If you are using the official Windows HDR Calibration app, do not blindly trust what it says your max luminance is.

The Windows app forces you to calibrate using a 10% window size. Because OLEDs aggressively dim at a 10% window, the test pattern will visually clip way below your monitor's true 1% peak (e.g., clipping at ~450 nits instead of your panel's actual capability unless your display has built-in tone mapping in which case the test may still clip at your monitor's true peak brightness). On my setup, because Gigabyte applies its own aggressive brightness boost on top of this, the test pattern actually clips as early as 380 nits!

If you set your max luminance to 400 nits based on that pattern, the OS reports this artificially low ceiling to your games. The game engine (or Windows Auto HDR) will then prematurely compress and tone map its HDR signal to fit inside that 400-nit container, meaning your peak brightness is functionally permanently capped at 400 nits. 

The same issue happens if you match your in-game sliders to the calibration app, which is a very common (but flawed) piece of advice. If I did that, I would never see highlights brighter than 380 nits, even in bright, high-APL scenes where the monitor's native brightness response is actually accurate. If I used that low peak setting alongside my ReShade correction, my absolute peak brightness would be permanently crippled to 380 nits across the board.

### The Fix:

I highly recommend bypassing these OS-level constraints entirely using [MHC ICC Profile Maker](https://github.com/ttys001/MHC-ICC-Profile-Maker).

Use the tool to create an ICC profile that mimics your EDID, but set the **Max** and **Max Full Frame Luminance** to **10,000 nits**.

This tells Windows and your games that your monitor has infinite HDR headroom. It forces the rendering pipeline to act as a pure passthrough, ensuring the raw, untampered HDR signal reaches ReShade so the shader can handle the math properly.

**Note:** This workaround isn't perfect. Many modern games rely on the Windows ICC profile to auto-configure their HDR limits. For those games, the internal peak brightness slider will default to 10,000 nits. You will just need to manually dial the in-game peak brightness (or the peak in tools like RenoDX/SpecialK) back down to your actual target (e.g., 1000 nits). Because of this, it's highly recommended to keep a second, accurately configured profile on hand for games that lack proper internal sliders (in my case, ~1050 nits max luminance and ~250 nits max full frame luminance).

## Generating Your Own LUT (For Calibrators)

A Python script (`process_lut.py`) is included in the `Toolkit` folder. If you have a colorimeter and HCFR:

1. Use madTPG as your test pattern generator.
2. Run a sweep of CAPL tests. For the best interpolation results, keep these rules in mind:
   * You **must** run a sweep on a black background to stand in as 0% APL.
   * You **must** run a sweep on a white background to stand in as 100% APL.
   * Run the sweeps with the smallest window size you can (I used 1%).
3. Export the sweeps as CSV files named `XX%CAPL.GrayScaleSheet.csv`.
4. Place the CSVs in the same folder as the Python script.
5. Open `process_lut.py` in a text editor and edit the `apl_levels` array to reflect the exact APL percentages you tested.
6. Run the script to generate your custom `EOTF_Correction_LUT.png`. *(Example calibration data is provided in the `Data` folder to show the expected format).*

---

*This work is licensed under Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International. To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/4.0/*