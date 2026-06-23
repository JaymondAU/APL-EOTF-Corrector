/*
    EOTF Correction LUT Pipeline
    ================================================================
    A hybrid QD-OLED ABL Fixer.
    
    This shader introduces two major performance and accuracy innovations:
    1. Hardware MipMap APL Calculation: Leverages the GPU's fixed-function 
       texture hardware to instantly average 1,048,576 pixels down to a 1x1 
       MipMap, avoiding expensive manual `for` loops and missed highlights.
    2. Offline HCFR EOTF Inverse LUT: Uses Python and Scipy to generate a mathematically 
       perfect inversion of the display's physical Auto Brightness Limiter (ABL) dimming 
       curve, bypassing the need for manual curve guessing inside the shader.

    Credits:
    - Jaymond: Hardware MipMap APL calculation & Python HCFR EOTF Inverse LUT.
    - MSpeedo: Concept of the Closed-Loop Display State Solver for ABL compensation, 
      along with the mathematical framework for BT.2390 Tonemapping and temporal logic.
    - ShanSolox: Refinements to Tonemapping and Color-Preserving Hue Limits.
    - DespairArdor: Original inspiration for ReShade-based APL tracking.

    ================================================================
    LICENSE INFORMATION
    ================================================================
    
    The primary code for this shader (Hardware MipMap APL calculation and 
    LUT implementation) is licensed under:
    
    Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)
    https://creativecommons.org/licenses/by-nc-sa/4.0/

    ---

    Portions of this code (BT.2390 Tonemapping, Color-Preserving Hue Limits, 
    and temporal smoothing math) are adapted from works by ShanSolox, MSpeedo, 
    and DespairArdor. Those specific portions are covered under the following license:

    MIT License
    Copyright (c) 2025 DespairArdor

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
*/

#include "ReShade.fxh"

// =========================================================================
// UNIFORMS (USER INTERFACE)
// =========================================================================

#ifndef BUFFER_COLOR_SPACE
    #define BUFFER_COLOR_SPACE 0
#endif

#if BUFFER_COLOR_SPACE == 2
    #define DEFAULT_INPUT_MODE 0 // scRGB
#else
    #define DEFAULT_INPUT_MODE 1 // HDR10 PQ
#endif

// --- Global Settings ---
uniform int APLInputMode <
    ui_category = "Global Settings";
    ui_type = "combo";
    ui_items = "scRGB Normalized\0PQ Decoded Normalized\0";
    ui_label = "APL Input Mode";
> = DEFAULT_INPUT_MODE;

uniform float SIGNAL_REFERENCE_NITS <
    ui_category = "Global Settings";
    ui_type = "slider";
    ui_min = 1.0; ui_max = 200.0; ui_step = 1.0;
    ui_label = "scRGB Signal Reference (nits)";
> = 80.0;

uniform float ABL_Attack_Time <
    ui_category = "Global Settings";
    ui_type = "slider";
    ui_min = 0.0; ui_max = 2000.0; ui_step = 10.0;
    ui_label = "ABL Attack Time (ms)";
    ui_tooltip = "How fast the monitor dims when the screen gets suddenly bright (Usually very fast).";
> = 50.0;

uniform float ABL_Release_Time <
    ui_category = "Global Settings";
    ui_type = "slider";
    ui_min = 0.0; ui_max = 2000.0; ui_step = 10.0;
    ui_label = "ABL Release Time (ms)";
    ui_tooltip = "How fast the monitor brightens when the screen gets dark (Usually slower to prevent flashing).";
> = 250.0;

uniform bool DebugAPL <
    ui_category = "Global Settings";
    ui_label = "Show calculated APL as a color";
> = false;

// --- Color Preservation (Optional) ---
uniform bool EnableColorPreservation <
    ui_spacing = 1;
    ui_category = "Color Preservation (Optional)";
    ui_label = "Enable Color Preservation";
    ui_tooltip = "Limits boost on bright colors to prevent hue shifting as they hit the monitor's physical limit. WARNING: Can cause inconsistent luminance.";
> = false;

uniform float PEAK_MONITOR_NITS <
    ui_category = "Color Preservation (Optional)";
    ui_type = "slider";
    ui_min = 400.0; ui_max = 2000.0; ui_step = 10.0;
    ui_label = "Monitor Peak Brightness (nits)";
> = 1000.0;

// --- BT.2390 Tonemapping (Optional) ---
uniform bool EnableTonemapping <
    ui_spacing = 1;
    ui_category = "BT.2390 Tonemapping (Optional)";
    ui_label = "Enable Tonemapping";
    ui_tooltip = "Smoothly compresses highlights. Only use this if the game lacks a peak brightness slider or RenoDX mod to manage its own highlights.";
> = false;

uniform float TM_InputPeak <
    ui_category = "BT.2390 Tonemapping (Optional)";
    ui_type = "slider";
    ui_min = 400.0; ui_max = 10000.0; ui_step = 10.0;
    ui_label = "Input Peak Brightness (nits)";
> = 4000.0;

uniform float TM_OutputPeak <
    ui_category = "BT.2390 Tonemapping (Optional)";
    ui_type = "slider";
    ui_min = 400.0; ui_max = 4000.0; ui_step = 10.0;
    ui_label = "Output Peak Brightness (nits)";
> = 1000.0;

uniform float TM_Shape <
    ui_category = "BT.2390 Tonemapping (Optional)";
    ui_type = "slider";
    ui_min = 0.25; ui_max = 4.0; ui_step = 0.05;
    ui_label = "Tonemapping Roll-Off Shape";
    ui_tooltip = "1.0 = standard BT.2390. Lower = starts later, holds highlights higher. Higher = starts earlier, compresses harder.";
> = 1.0;

uniform float FrameTime < source = "frametime"; >;

// =========================================================================
// ST 2084 (PQ) CONSTANTS & FUNCTIONS
// =========================================================================

static const float m1 = 2610.0 / 16384.0;
static const float m2 = (2523.0 / 4096.0) * 128.0;
static const float c1 = 3424.0 / 4096.0;
static const float c2 = (2413.0 / 4096.0) * 32.0;
static const float c3 = (2392.0 / 4096.0) * 32.0;

static const float3x3 sRGB_2_BT2020 = float3x3(
    0.6274040, 0.3292820, 0.0433136,
    0.0690970, 0.9195400, 0.0113612,
    0.0163916, 0.0880132, 0.8955950
);

static const float PQ_BLACK = 7.309559025783966e-07;

float3 pq_to_linear(float3 pq) 
{
    float3 pq_pow = pow(max(pq, 0.0), 1.0 / m2);
    float3 num = max(pq_pow - c1, 0.0);
    float3 den = c2 - c3 * pq_pow;
    return pow(max(num / den, 0.0), 1.0 / m1);
}

float pq_to_linear_scalar(float pq) 
{
    float pq_pow = pow(max(pq, 0.0), 1.0 / m2);
    float num = max(pq_pow - c1, 0.0);
    float den = c2 - c3 * pq_pow;
    return pow(max(num / den, 0.0), 1.0 / m1);
}

float3 linear_to_pq(float3 lin) 
{
    float3 lin_pow = pow(max(lin, 0.0), m1);
    float3 num = c1 + c2 * lin_pow;
    float3 den = 1.0 + c3 * lin_pow;
    return pow(max(num / den, 0.0), m2);
}

float linear_to_pq_scalar(float lin) 
{
    float lin_pow = pow(max(lin, 0.0), m1);
    float num = c1 + c2 * lin_pow;
    float den = 1.0 + c3 * lin_pow;
    return pow(max(num / den, 0.0), m2);
}

// =========================================================================
// BT.2390 TONEMAPPING MATH
// =========================================================================

float ComputeBT2390ShapedKneeStart(float maxLum, float shapeControl)
{
    float standardKneeStart = saturate(1.5 * maxLum - 0.5);

    if (abs(shapeControl - 1.0) <= 1e-4) return standardKneeStart;

    float safeShapeControl = max(shapeControl, 1e-4);
    float shapeBias = log2(safeShapeControl);

    if (shapeBias > 0.0)
    {
        float hardT = saturate(shapeBias * 0.5);
        float aggressiveKneeStart = standardKneeStart * 0.15;
        return saturate(lerp(standardKneeStart, aggressiveKneeStart, hardT));
    }
    
    if (shapeBias < 0.0)
    {
        float softT = saturate(-shapeBias * 0.5);
        float softerKneeStart = standardKneeStart + (maxLum - standardKneeStart) * 0.85;
        return min(lerp(standardKneeStart, softerKneeStart, softT), maxLum - 1e-6);
    }
    return standardKneeStart;
}

float ApplyBT2390EETFToPQWithShape(float inputPQ, float sourcePeakNits, float targetPeakNits, float shapeControl)
{
    float safeSourcePeakNits = max(sourcePeakNits, 1e-4);
    float safeTargetPeakNits = max(targetPeakNits, 0.0);

    if (safeTargetPeakNits <= 0.0) return PQ_BLACK;
    if (safeTargetPeakNits >= safeSourcePeakNits - 1e-4) return saturate(inputPQ);

    float sourceBlackPQ = PQ_BLACK;
    float sourceWhitePQ = max(linear_to_pq_scalar(safeSourcePeakNits / 10000.0), sourceBlackPQ + 1e-6);
    float targetWhitePQ = min(linear_to_pq_scalar(safeTargetPeakNits / 10000.0), sourceWhitePQ - 1e-6);

    float pqRange = max(sourceWhitePQ - sourceBlackPQ, 1e-6);
    float e1 = saturate((saturate(inputPQ) - sourceBlackPQ) / pqRange);
    float maxLum = saturate((targetWhitePQ - sourceBlackPQ) / pqRange);

    if (maxLum >= 1.0 - 1e-6) return saturate(inputPQ);

    float kneeStart = ComputeBT2390ShapedKneeStart(maxLum, shapeControl);
    float e2 = e1;

    if (e1 >= kneeStart)
    {
        float shoulderSpan = max(1.0 - kneeStart, 1e-6);
        float compressionSpan = max(maxLum - kneeStart, 1e-6);
        float u = saturate((e1 - kneeStart) / shoulderSpan);
        float shoulderPower = max(shoulderSpan / compressionSpan, 1.0);

        e2 = kneeStart + compressionSpan * (1.0 - pow(1.0 - u, shoulderPower));
    }

    return saturate(e2 * pqRange + sourceBlackPQ);
}

// =========================================================================
// TEXTURES & SAMPLERS
// =========================================================================

texture TexCorrectionLUT < source = "EOTF_Correction_LUT.png"; > { Width = 1024; Height = 1024; Format = RGBA8; SRGB = false; };
sampler SamplerLUT { Texture = TexCorrectionLUT; MinFilter = LINEAR; MagFilter = LINEAR; AddressU = CLAMP; AddressV = CLAMP; };

texture TexPostLinearLuminance { Width = 1024; Height = 1024; Format = R32F; MipLevels = 11; };
sampler SamplerPostLinearLuminance { Texture = TexPostLinearLuminance; MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = LINEAR; };

texture TexAPL { Width = 1; Height = 1; Format = R32F; };
sampler SamplerAPL { Texture = TexAPL; MinFilter = POINT; MagFilter = POINT; };

texture TexAPL_Prev { Width = 1; Height = 1; Format = R32F; };
sampler SamplerAPL_Prev { Texture = TexAPL_Prev; MinFilter = POINT; MagFilter = POINT; };

// =========================================================================
// SHADER PASSES
// =========================================================================

// Pass 1: Save the previous frame's smoothed APL to prepare for manual blending
void PS_CopyAPL(float4 pos : SV_Position, float2 texcoord : TEXCOORD, out float apl_out : SV_Target)
{
    apl_out = tex2D(SamplerAPL, float2(0.5, 0.5)).r;
}

// Pass 2: Apply the LUT correction to the BackBuffer using the current state
void PS_ApplyCorrection(float4 pos : SV_Position, float2 texcoord : TEXCOORD, out float4 output : SV_Target)
{
    float4 color = tex2D(ReShade::BackBuffer, texcoord);
    float current_state_apl = tex2D(SamplerAPL_Prev, float2(0.5, 0.5)).r; // Uses last frame's fully solved state
    float4 final_color;
    
    float3 lin_rgb;

    if (APLInputMode == 1) // HDR10
    {
        lin_rgb = pq_to_linear(color.rgb);
    }
    else // scRGB
    {
        lin_rgb = color.rgb * (SIGNAL_REFERENCE_NITS / 10000.0);
    }

    if (EnableTonemapping)
    {
        float max_nits = max(lin_rgb.r, max(lin_rgb.g, lin_rgb.b)) * 10000.0;
        if (max_nits > 0.0) 
        {
            float pq_max = linear_to_pq_scalar(max_nits / 10000.0);
            float mapped_pq_max = ApplyBT2390EETFToPQWithShape(pq_max, TM_InputPeak, TM_OutputPeak, TM_Shape);
            float mapped_max_nits = pq_to_linear_scalar(mapped_pq_max) * 10000.0;
            lin_rgb *= (mapped_max_nits / max_nits);
        }
    }

    float lin_luminance;
    if (APLInputMode == 1)
    {
        lin_luminance = dot(lin_rgb, float3(0.2627, 0.6780, 0.0593));
    }
    else
    {
        lin_luminance = dot(lin_rgb, float3(0.2126, 0.7152, 0.0722));
    }
    
    float pq_luminance = linear_to_pq_scalar(lin_luminance);
    
    float2 packed_luminance = tex2D(SamplerLUT, float2(pq_luminance, current_state_apl)).rg;
    float corrected_pq_luminance = packed_luminance.r * (65280.0 / 65535.0) + packed_luminance.g * (255.0 / 65535.0);
    
    float corrected_lin_luminance = pq_to_linear_scalar(corrected_pq_luminance);
    float scale = corrected_lin_luminance / max(lin_luminance, 1e-8);
    
    if (EnableColorPreservation)
    {
        float max_rgb_channel;
        if (APLInputMode == 0) // scRGB uses sRGB primaries, convert to BT.2020 to correctly evaluate peak channel
        {
            float3 lin_rgb_2020 = mul(sRGB_2_BT2020, lin_rgb);
            max_rgb_channel = max(lin_rgb_2020.r, max(lin_rgb_2020.g, lin_rgb_2020.b));
        }
        else
        {
            max_rgb_channel = max(lin_rgb.r, max(lin_rgb.g, lin_rgb.b));
        }

        float normalized_peak_limit = PEAK_MONITOR_NITS / 10000.0;
        float max_hue_preserving_scale = normalized_peak_limit / max(max_rgb_channel, 1e-8);
        scale = min(scale, max(max_hue_preserving_scale, 1.0));
    }

    float3 scaled_lin_rgb = lin_rgb * scale;

    if (APLInputMode == 1) final_color = float4(linear_to_pq(scaled_lin_rgb), color.a);
    else final_color = float4(scaled_lin_rgb * (10000.0 / SIGNAL_REFERENCE_NITS), color.a);
    
    output = DebugAPL ? float4(current_state_apl.xxx, 1.0) : final_color;
}

// Pass 3: Convert the corrected BackBuffer to Linear Luminance and generate Hardware MipMaps
void PS_StoreLinearLuminance(float4 pos : SV_Position, float2 texcoord : TEXCOORD, out float lin_luminance_out : SV_Target)
{
    float4 color = tex2D(ReShade::BackBuffer, texcoord);
    
    if (APLInputMode == 1)
    {
        float3 lin_rgb = pq_to_linear(color.rgb);
        lin_luminance_out = dot(lin_rgb, float3(0.2627, 0.6780, 0.0593));
    }
    else
    {
        float3 lin_rgb = color.rgb * (SIGNAL_REFERENCE_NITS / 10000.0);
        float3 luma_coeffs = float3(0.2126, 0.7152, 0.0722);
        lin_luminance_out = dot(lin_rgb, luma_coeffs);
    }
}

// Pass 4: Calculate Closed-Loop APL (Manual Temporal Blend using separate Attack/Release times)
void PS_CalculateAPL(float4 pos : SV_Position, float2 texcoord : TEXCOORD, out float apl_out : SV_Target)
{
    float new_hardware_lin_apl = tex2Dlod(SamplerPostLinearLuminance, float4(0.5, 0.5, 0, 10.0)).r;
    float new_hardware_pq_apl = linear_to_pq_scalar(new_hardware_lin_apl);
    
    float previous_apl = tex2D(SamplerAPL_Prev, float2(0.5, 0.5)).r;
    
    // Choose Attack or Release speed based on whether the screen is getting brighter or darker
    float target_smoothing_ms = (new_hardware_pq_apl > previous_apl) ? ABL_Attack_Time : ABL_Release_Time;
    
    // Framerate Independent Exponential Moving Average
    float blend_alpha = (target_smoothing_ms <= 0.0) ? 1.0 : 1.0 - exp(-FrameTime / target_smoothing_ms);
    
    apl_out = lerp(previous_apl, new_hardware_pq_apl, blend_alpha);
}

// =========================================================================
// TECHNIQUES
// =========================================================================

technique QDOLED_EOTF_LUT_Fix
{
    pass CopyAPL
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_CopyAPL;
        RenderTarget = TexAPL_Prev;
    }

    pass ApplyCorrection
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_ApplyCorrection;
    }
    
    pass StoreLinearLuminance
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_StoreLinearLuminance;
        RenderTarget = TexPostLinearLuminance;
        GenerateMipMaps = true;
    }
    
    pass CalculateAPL
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_CalculateAPL;
        RenderTarget = TexAPL;
    }
}