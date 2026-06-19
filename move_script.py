import os
import shutil

base = "c:\\Users\\Jaymond\\Documents\\PC Gaming Optimised\\MO27Q2\\APL-EOTF-Corrector"

def move_files(src_dir, dest_dir):
    src = os.path.join(base, src_dir)
    dest = os.path.join(base, dest_dir)
    if not os.path.exists(dest):
        os.makedirs(dest, exist_ok=True)
    if os.path.exists(src):
        for f in os.listdir(src):
            src_file = os.path.join(src, f)
            if os.path.isfile(src_file):
                shutil.copy2(src_file, dest)
                try:
                    os.remove(src_file)
                except Exception as e:
                    print(f"Could not remove {src_file}: {e}")
        try:
            os.rmdir(src)
        except:
            pass

move_files("Data\\Gigabyte MO27Q2\\HDR Peak 1000", "Profiles\\Gigabyte\\MO27Q2\\HDR Peak 1000\\Measurements")
move_files("Data\\Gigabyte MO27Q2\\HDR+APL_HIGH", "Profiles\\Gigabyte\\MO27Q2\\HDR+APL_HIGH\\Measurements")
move_files("Data\\Gigabyte MO27Q2\\HDR+APL_MIDDLE", "Profiles\\Gigabyte\\MO27Q2\\HDR+APL_MIDDLE\\Measurements")

# Move the LUT
lut_src = os.path.join(base, "Textures\\Gigabyte_MO27Q2_HDR_PEAK_1000_EOTF_Correction_LUT.png")
lut_dest = os.path.join(base, "Profiles\\Gigabyte\\MO27Q2\\HDR Peak 1000\\EOTF_Correction_LUT.png")
if os.path.exists(lut_src):
    shutil.copy2(lut_src, lut_dest)
    try:
        os.remove(lut_src)
    except:
        pass

try:
    os.rmdir(os.path.join(base, "Data\\Gigabyte MO27Q2"))
    os.rmdir(os.path.join(base, "Data"))
    os.rmdir(os.path.join(base, "Textures"))
except:
    pass

print("Done moving files!")
