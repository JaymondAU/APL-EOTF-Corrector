# Gigabyte MO27Q2 - HDR Peak 1000

This folder contains the EOTF Correction LUT specifically profiled for the Gigabyte MO27Q2.

## Required Monitor OSD Settings

For this LUT to mathematically correct the display's EOTF curve accurately, your monitor **must** be set to the exact settings used during calibration:

*   **Picture Mode**: HDR Peak 1000
*   **Dark Enhance**: OFF
*   All other relevant monitor settings left at factory defaults.

Using this LUT in other picture modes (such as HDR+APL High) will not produce accurate tracking.

## Usage

1. Copy the `EOTF_Correction_LUT.png` from this folder.
2. Rename it to exactly **`EOTF_Correction_LUT.png`** (if not already named as such).
3. Place the image into your game's `reshade-shaders\Textures` folder.
