import numpy as np
import pandas as pd
from scipy.interpolate import PchipInterpolator
import imageio
import matplotlib.pyplot as plt
import os

# --- ST 2084 (PQ) Math ---
m1 = 2610 / 16384
m2 = (2523 / 4096) * 128
c1 = 3424 / 4096
c2 = (2413 / 4096) * 32
c3 = (2392 / 4096) * 32

def pq_to_nits(v):
    v = np.clip(v, 0.0, 1.0)
    num = np.maximum(v**(1/m2) - c1, 0)
    den = c2 - c3 * v**(1/m2)
    return ((num / den)**(1/m1)) * 10000.0

# --- Configuration ---
apl_levels = [0, 1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100]
csv_folder = "./" 
LUT_SIZE = 1024

lut_image = np.zeros((LUT_SIZE, LUT_SIZE), dtype=np.float32)
apl_curves_generated = []
loaded_apls = []

sim_targets = []
sim_corrected = []

print("Starting data processing...")

for apl in apl_levels:
    filepath = os.path.join(csv_folder, f"{apl}%CAPL.GrayScaleSheet.csv")
    
    if not os.path.exists(filepath):
        print(f"  -> File {filepath} not found, skipping...")
        continue
        
    # FIX: index_col=0 and .T tells Pandas to rotate the HCFR spreadsheet 90 degrees!
    df = pd.read_csv(filepath, sep=';', decimal='.', index_col=0).T
    
    # FIX: .astype(float) ensures the data is strictly read as math numbers
    stimulus_sent = df['% White'].astype(float).values / 100.0
    measured_nits = df['Y'].astype(float).values
    
    # --- DATA CLEANING: Enforce strict monotonicity for the math ---
    clean_nits = [measured_nits[0]]
    clean_stim = [stimulus_sent[0]]
    
    for i in range(1, len(measured_nits)):
        if measured_nits[i] > clean_nits[-1]: 
            clean_nits.append(measured_nits[i])
            clean_stim.append(stimulus_sent[i])
            
    clean_nits = np.array(clean_nits)
    clean_stim = np.array(clean_stim)
    
    # Create the inverse interpolator
    inv_eotf = PchipInterpolator(clean_nits, clean_stim)
    corrected_signal_row = np.zeros(LUT_SIZE)
    
    for i in range(LUT_SIZE):
        target_signal = i / (LUT_SIZE - 1)
        target_nits = pq_to_nits(target_signal)
        
        # Clamp to the maximum clean nits to adapt to the shifting ABL ceiling
        clamped_nits = min(target_nits, clean_nits[-1])
        
        required_signal = inv_eotf(clamped_nits)
        corrected_signal_row[i] = np.clip(required_signal, 0.0, 1.0)
        
    apl_curves_generated.append(corrected_signal_row)
    loaded_apls.append(apl)
    
    # --- VERIFICATION DATA GENERATION (Using 2% APL for the plot) ---
    if apl == 2:
        sim_targets = [pq_to_nits(x) for x in np.linspace(0, 1, 100)]
        sim_signals = [inv_eotf(min(n, clean_nits[-1])) for n in sim_targets]
        forward_eotf = PchipInterpolator(clean_stim, clean_nits)
        sim_corrected = [forward_eotf(s) for s in sim_signals]
        print("  -> Verification data locked for 2% APL.")

if len(apl_curves_generated) == 0:
    print("Error: No CSV files were loaded! Check your file names.")
    exit()

print(f"Successfully processed {len(loaded_apls)} APL files. Generating LUT...")

# Convert lists to arrays for vertical interpolation
apl_curves_generated = np.array(apl_curves_generated)
apl_fractions = np.array(loaded_apls) / 100.0
target_apl_axis = np.linspace(0.0, 1.0, LUT_SIZE)

# Interpolate vertically to fill the 1024x1024 grid smoothly
for col in range(LUT_SIZE):
    col_data = apl_curves_generated[:, col]
    vertical_interpolator = PchipInterpolator(apl_fractions, col_data)
    lut_image[:, col] = vertical_interpolator(target_apl_axis)

# Save as standard 8-bit RGB PNG with 16-bit packed data
lut_image_16bit = np.clip(lut_image * 65535.0, 0, 65535).astype(np.uint16)
lut_image_rgb = np.zeros((LUT_SIZE, LUT_SIZE, 3), dtype=np.uint8)

# Split the 16-bit integer into two 8-bit channels
lut_image_rgb[:,:,0] = (lut_image_16bit >> 8) & 0xFF  # Red channel = High byte
lut_image_rgb[:,:,1] = lut_image_16bit & 0xFF         # Green channel = Low byte
lut_image_rgb[:,:,2] = 0                              # Blue channel = Unused

imageio.imwrite("QDOLED_Correction_LUT.png", lut_image_rgb)

print("===================================================")
print("SUCCESS: QDOLED_Correction_LUT.png has been created!")
print("===================================================")
print("Close the graph window to finish the script.")

# Plot the Verification Graph
plt.style.use('dark_background')
plt.figure(figsize=(10, 6))
plt.title("Shader Mathematical Verification (2% APL)", fontsize=14)
plt.plot(sim_targets, sim_targets, 'w--', alpha=0.5, label="Creator's Intent (ST.2084 PQ)")
plt.plot(sim_targets, sim_corrected, 'g-', linewidth=2, label="Your Monitor with ReShade LUT")
plt.xlabel("Intended Nits (Game Engine Output)", fontsize=12)
plt.ylabel("Actual Display Nits", fontsize=12)
plt.xlim(0, 1200)
plt.ylim(0, 1200)
plt.legend(fontsize=12)
plt.grid(True, alpha=0.2)
plt.tight_layout()
plt.show()