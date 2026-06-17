# APL-EOTF-Corrector

A 2D LUT-based ReShade shader and Python script to help correct APL-dependent HDR EOTF tracking errors.


**Disclaimer:** The code for this project (both the HLSL shader and Python script) was heavily vibe coded with Google Gemini.


## The Included LUT (Gigabyte MO27Q2 QD-OLED)

The `Gigabyte\_MO27Q2\_EOTF\_Correction\_LUT.png` included in this repository by default was calibrated specifically for the **Gigabyte MO27Q2 in its Peak 1000 mode**.

Out of the box, this monitor tracks the PQ EOTF curve fairly accurately in high APL (bright) scenes, but aggressively over-brightens the midtones and highlights in low APL (dark) scenes. This LUT tries to restore fairly accurate EOTF tracking across all APLs.

If you are using a different monitor, this specific LUT probably won't look correct, but you can use the included Python toolkit to generate one for your own display.

## How to Install \& Use

1. Install [ReShade](https://reshade.me/) to your game with full add-on support.
2. Download this repository.
3. Place `APL\_EOTF\_Corrector.fx` into your game's `reshade-shaders\\Shaders` folder.
4. Rename `Gigabyte\_MO27Q2\_EOTF\_Correction\_LUT.png` to exactly **`EOTF\_Correction\_LUT.png`**.
5. Place this renamed image into your game's `reshade-shaders\\Textures` folder.
6. Launch the game and open the ReShade menu.
7. Enable **APL\_EOTF\_Corrector**. Make sure the `APL Input Mode` in the shader settings matches your game's HDR format (PQ/HDR10 or scRGB).

## Generating Your Own LUT (For Calibrators)

A Python script (`process\_lut.py`) is included in the `Toolkit` folder. If you have a colorimeter and HCFR:

1. Use madTPG as your test pattern generator.
2. Run a sweep of CAPL tests. For the best interpolation results, keep these rules in mind:

   * You **must** run a sweep on a black background to stand in as 0% APL.
   * You **must** run a sweep on a white background to stand in as 100% APL.
   * Run the sweeps with the smallest window size you can (I used 1%).
3. Export the sweeps as CSV files named `XX%CAPL.GrayScaleSheet.csv`.
4. Place the CSVs in the same folder as the Python script.
5. Open `process\_lut.py` in a text editor and edit the `apl\_levels` array to reflect the exact APL percentages you tested.
6. Run the script to generate your custom `EOTF\_Correction\_LUT.png`. *(Example calibration data is provided in the `Data` folder to show the expected format).*

\---



*This work is licensed under Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International. To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/4.0/*

