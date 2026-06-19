"""
EOTF Correction LUT Generator
================================================================
Based on the QD-OLED APL Fixer concepts by DespairArdor, MSpeedo, and ShanSolox.
LUT Logic and Python Implementation by Jaymond.

License:
Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)
https://creativecommons.org/licenses/by-nc-sa/4.0/
"""

import numpy as np
import pandas as pd
from scipy.interpolate import PchipInterpolator
import imageio.v2 as imageio
import os
import glob
import re

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

# --- Configuration & File Loading ---
input_dir = "./" 
output_dir = "./"
LUT_SIZE = 1024

# Auto-detect available HCFR Sweeps dynamically
file_dict = {}
for filepath in glob.glob(os.path.join(input_dir, "*%CAPL.GrayScaleSheet.csv")):
    match = re.search(r'(\d+)%CAPL', os.path.basename(filepath))
    if match:
        file_dict[int(match.group(1))] = filepath

apl_levels = sorted(file_dict.keys())
lut_image = np.zeros((LUT_SIZE, LUT_SIZE), dtype=np.float32)
apl_curves_generated = []
loaded_apls = []

print(f"Starting data processing. Found {len(apl_levels)} APL files...")

for apl in apl_levels:
    filepath = file_dict[apl]
    df = pd.read_csv(filepath, sep=';', decimal='.', index_col=0).T
    
    stimulus_sent = df['% White'].astype(float).values / 100.0
    measured_nits = df['Y'].astype(float).values
    
    # Enforce strict monotonicity
    clean_nits = [measured_nits[0]]
    clean_stim = [stimulus_sent[0]]
    
    for i in range(1, len(measured_nits)):
        if measured_nits[i] > clean_nits[-1]: 
            clean_nits.append(measured_nits[i])
            clean_stim.append(stimulus_sent[i])
            
    clean_nits = np.array(clean_nits)
    clean_stim = np.array(clean_stim)
    
    inv_eotf = PchipInterpolator(clean_nits, clean_stim)
    corrected_signal_row = np.zeros(LUT_SIZE)
    
    for i in range(LUT_SIZE):
        target_signal = i / (LUT_SIZE - 1)
        target_nits = pq_to_nits(target_signal)
        clamped_nits = min(target_nits, clean_nits[-1])
        required_signal = inv_eotf(clamped_nits)
        corrected_signal_row[i] = np.clip(required_signal, 0.0, 1.0)
        
    apl_curves_generated.append(corrected_signal_row)
    loaded_apls.append(apl)

if len(apl_curves_generated) == 0:
    print("Error: No CSV files were loaded! Check your file names.")
    exit()

# Interpolate vertically
apl_curves_generated = np.array(apl_curves_generated)
apl_fractions = np.array(loaded_apls) / 100.0
target_apl_axis = np.linspace(0.0, 1.0, LUT_SIZE)

for col in range(LUT_SIZE):
    col_data = apl_curves_generated[:, col]
    vertical_interpolator = PchipInterpolator(apl_fractions, col_data)
    lut_image[:, col] = vertical_interpolator(target_apl_axis)

# --- RGBA8 PACKING FOR RESHADE COMPATIBILITY ---
lut_image_16bit = np.clip(np.round(lut_image * 65535.0), 0, 65535).astype(np.uint16)
lut_image_rgb = np.zeros((LUT_SIZE, LUT_SIZE, 3), dtype=np.uint8)
lut_image_rgb[:,:,0] = (lut_image_16bit >> 8) & 0xFF  # Red channel = High byte
lut_image_rgb[:,:,1] = lut_image_16bit & 0xFF         # Green channel = Low byte
lut_image_rgb[:,:,2] = 0                              # Blue channel = Unused

output_path = os.path.join(output_dir, "EOTF_Correction_LUT.png")
imageio.imwrite(output_path, lut_image_rgb)

print("===================================================")
print("SUCCESS: EOTF_Correction_LUT.png has been created!")
print("===================================================")