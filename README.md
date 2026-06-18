# APL-EOTF-Corrector

A 2D LUT-based ReShade shader and Python script to help correct APL-dependent HDR EOTF tracking errors.

**Disclaimer:** The code for this project (both the HLSL shader and Python script) was heavily vibe-coded with Google Gemini.

## The Included LUT (Gigabyte MO27Q2 QD-OLED)

The `Gigabyte_MO27Q2_EOTF_Correction_LUT.png` included in this repository by default was calibrated specifically for my **Gigabyte MO27Q2 in its Peak 1000 mode**.

Out of the box, this monitor tracks the PQ EOTF curve fairly accurately in high APL (bright) scenes, but aggressively over-brightens the midtones and highlights in low APL (dark) scenes. This LUT attempts to restore mathematically accurate EOTF tracking across all APLs.

If you are using a different monitor, this specific LUT probably won't look correct. However, you can use the included Python toolkit to generate one for your own display if you have a colorimeter. I used an X-Rite i1 Display Pro that I bought used for $220 AUD.

## Don't Have a Colorimeter? (Alternatives & Credits)

This specific shader is built around HCFR hardware measurements. If you don't own a colorimeter to generate a custom LUT for your panel, I highly recommend checking out these fantastic alternative shaders that inspired this project. They use advanced mathematical models to achieve brilliant results using manual data entry:

* **[LumaBoost by Valadore](https://github.com/Valadore/LumaBoost)**: A high-fidelity display-hardware emulator. If you don't have a colorimeter, you can simply look up your monitor's window brightness specs on RTINGS (1% to 100% nits) and type them into the UI to generate a custom ABL model. It's packed with advanced features like shadow protection, skin-tone masking, and contrast recovery.
* **[EOTF Boost by MSpeedo](https://github.com/mspeedo/QD-OLED-APL-FIXER) & [ShanSolox](https://github.com/shansolox/QD-OLED-APL-FIXER)**: Highly advanced shaders featuring 1D APL lookups, BT.2390 Tonemapping, and Color-Preserving Hue Limits.
* **[EOTF Boost by DespairArdor](https://github.com/DespairArdor/QD-OLED-APL-FIXER)**: The original ReShade APL tracking shader that inspired this entire movement.

*Massive credit to these developers. The temporal smoothing, BT.2390 tonemapping, and color-preserving math embedded in this shader were adapted directly from the groundwork laid by MSpeedo and ShanSolox.*

## How to Install & Use

1. Install [ReShade](https://reshade.me/) to your game.
2. Download this repository.
3. Place `APL_EOTF_Corrector.fx` into your game's `reshade-shaders\Shaders` folder.
4. Rename `Gigabyte_MO27Q2_EOTF_Correction_LUT.png` to exactly **`EOTF_Correction_LUT.png`**.
5. Place this renamed image into your game's `reshade-shaders\Textures` folder.
6. Launch the game and open the ReShade menu.
7. Enable **APL_EOTF_Corrector**. Make sure it is placed at the **very bottom** of your active effect list so it applies after all other effects.
8. Make sure the `APL Input Mode` in the shader settings matches your game's HDR format (PQ/HDR10 or scRGB). *(Note: If using scRGB, leave the `scRGB Signal Reference` at 80 for most games, but adjust it if the midtones look completely washed out).*

## A Warning About the Windows HDR Calibration App

If you are using the official Windows HDR Calibration app, do not blindly trust what it says your max luminance is. It entirely depends on how your specific monitor handles its firmware during a 10% window test. 

*(Note: Specific nit values used below are illustrative examples. Panel capabilities vary wildly, ranging from VESA DisplayHDR True Black 400 certifications up to panels capable of reaching 1500+ nits).*

**1. Monitors that Hard-Clip (No Tone Mapping)**  
Because of ABL (Auto Brightness Limiter), an OLED panel's physical peak brightness on a 10% window is always significantly lower than its true 1% peak highlight capability. For example, a display that can hit 1000 nits on a tiny 1% window might hit a physical ABL wall at 450 nits on a 10% window.

If your monitor tracks the EOTF perfectly and hard-clips at its physical limit, the test pattern in the Windows app will clip at that lower 10% limit. If you save that profile, Windows tells games your absolute peak capability is capped at that lower number. When a tiny 1% highlight occurs that your panel is physically capable of blasting to its true peak, the OS artificially caps the signal at the lower 10% limit. Your highlight range is artificially limited. *(True Category 1 monitors are actually quite rare in the PC space, with LG OLED TVs in HGiG mode being the closest true example).*

**2. Monitors with Built-In Tone Mapping (Compressive & Expansive)**  
Many modern displays use internal dynamic tone mapping to get around the hard-clipping issue. This usually takes two forms:
* **Compressive:** The monitor takes a signal up to its rated peak (e.g., 1000 nits) and compresses it down to fit inside whatever lower brightness the panel can physically output at 10%. Because of this, the Windows test pattern won't disappear until the slider actually hits the display's true rated peak. This safely preserves a larger peak container for the OS.
* **Expansive (Common on newer WOLEDs):** Some monitors will visually clip at a lower physical limit (e.g., 600 nits) during the Windows test. But when you are in a dark scene, the panel dynamically expands that capped 600-nit signal up to its 1% peak brightness limit (e.g., 1000 nits). While you keep your bright highlights, **you lose rendering precision and color volume**. Because the OS told the game your peak was 600 nits, the game engine squashed all its highlight detail into a 600-nit container. The monitor stretching it back out to 1000 nits just makes a compressed signal brighter; it cannot restore the engine-level gradations that were permanently lost. 

**3. The Gigabyte MO27Q2 (Aggressive EOTF Boost)**  
On my setup, the Gigabyte MO27Q2 doesn't use standard tone mapping. It uses a rudimentary EOTF boost. At a 10% window, the monitor hits its physical max of ~470 nits when receiving only a 380-nit signal. Because of the boost, the pattern disappears at 380. 

In-game, the OS caps the signal at 380 nits based on that calibration. But because of the EOTF boost, the monitor takes that 380-nit signal on a 1% window and artificially blasts it to ~1008 nits. You keep your bright highlights, but the EOTF tracking is completely ruined.

**Why my ReShade shader requires you to bypass this:**  
If you use my ReShade shader, it mathematically flattens this boost. The monitor stops cheating and tracks more accurately. It now behaves exactly like a Category 1 monitor (Hard-Clipping). A 380-nit signal will output exactly 380 nits. If you leave the Windows app capped at 380 nits while the shader is active, your absolute peak brightness will be permanently crippled to 380 nits across the board.

### The Fix: Force a 10,000 Nit Container

I highly recommend bypassing these OS-level constraints entirely using [MHC ICC Profile Maker](https://github.com/ttys001/MHC-ICC-Profile-Maker).

Use the tool to create an ICC profile that mimics your EDID, but set the **Max** and **Max Full Frame Luminance** to **10,000 nits**.

This tells Windows and your games that your monitor has infinite HDR headroom. It forces the rendering pipeline to act as a pure passthrough, ensuring the raw, untampered HDR signal reaches ReShade so the shader can handle the math properly.

**Note:** This workaround isn't perfect. Many modern games rely on the Windows ICC profile to auto-configure their HDR limits. For those games, the internal peak brightness slider will default to 10,000 nits. You will just need to manually dial the in-game peak brightness (or the peak in tools like RenoDX/SpecialK) back down to your actual target. 

Because of this, it is highly recommended to keep a second accurately configured profile on hand for games that lack proper internal sliders. 

## Generating Your Own LUT (For Calibrators)

A Python script (`process_lut.py`) is included in the `Toolkit` folder. 

**Prerequisites:** You will need Python installed. Install the required dependencies by running:
`pip install numpy pandas scipy imageio`

If you have a colorimeter and HCFR:

1. Use madTPG (included with madVR) or your preferred test pattern generator.
2. Run a sweep of CAPL tests. For the best interpolation results, keep these rules in mind:
   * You **must** run a sweep on a black background to stand in as 0% APL.
   * You **must** run a sweep on a white background to stand in as 100% APL.
   * Run the sweeps with the smallest window size you can (I used a 1% window).
3. Export the sweeps as CSV files named `XX%CAPL.GrayScaleSheet.csv`.
4. Place the CSVs in the same folder as the Python script.
5. Open `process_lut.py` in a text editor and edit the `apl_levels` array to reflect the exact APL percentages you tested.
6. Run the script to generate your custom `EOTF_Correction_LUT.png`. *(Example calibration data is provided in the `Data` folder to show the expected format).*

---

*This work is licensed under Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International. To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/4.0/*