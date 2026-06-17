#include "ReShade.fxh"

// =========================================================================
// UNIFORMS (USER INTERFACE)
// =========================================================================

// Fallback safeguard for older ReShade installations
#ifndef BUFFER_COLOR_SPACE
    #define BUFFER_COLOR_SPACE 0
#endif

// Set default value based on ReShade's auto-detected color space
// 2 = scRGB (Linear HDR), 3 = HDR10 ST2084 (PQ HDR)
#if BUFFER_COLOR_SPACE == 2
    #define DEFAULT_INPUT_MODE 0 // Default to scRGB Normalized
#else
    #define DEFAULT_INPUT_MODE 1 // Default to PQ Decoded Normalized (HDR10)
#endif

uniform int APLInputMode <
    ui_type = "combo";
    ui_items = "scRGB Normalized\0PQ Decoded Normalized\0";
    ui_label = "APL Input Mode";
> = DEFAULT_INPUT_MODE;

uniform float SIGNAL_REFERENCE_NITS <
    ui_type = "slider";
    ui_min = 1.0; ui_max = 200.0; ui_step = 1.0;
    ui_label = "scRGB Signal Reference (nits)";
> = 80.0;
uniform bool DebugAPL <
    ui_label = "Show calculated APL as a color";
> = false;

// =========================================================================
// ST 2084 (PQ) CONSTANTS & FUNCTIONS
// =========================================================================

static const float m1 = 2610.0 / 16384.0;
static const float m2 = (2523.0 / 4096.0) * 128.0;
static const float c1 = 3424.0 / 4096.0;
static const float c2 = (2413.0 / 4096.0) * 32.0;
static const float c3 = (2392.0 / 4096.0) * 32.0;

// Converts PQ (0.0 - 1.0) to Relative Linear (0.0 - 1.0, where 1.0 = 10,000 nits)
// Added abs() wraps to prevent compilation warnings for negative values
float3 pq_to_linear(float3 pq) 
{
    float3 pq_pow = pow(abs(max(pq, 0.0)), 1.0 / m2);
    float3 num = max(pq_pow - c1, 0.0);
    float3 den = c2 - c3 * pq_pow;
    return pow(abs(num / den), 1.0 / m1);
}

float pq_to_linear_scalar(float pq) 
{
    float pq_pow = pow(abs(max(pq, 0.0)), 1.0 / m2);
    float num = max(pq_pow - c1, 0.0);
    float den = c2 - c3 * pq_pow;
    return pow(abs(num / den), 1.0 / m1);
}

// Converts Relative Linear to PQ (0.0 - 1.0)
float3 linear_to_pq(float3 lin) 
{
    float3 lin_pow = pow(abs(max(lin, 0.0)), m1);
    float3 num = c1 + c2 * lin_pow;
    float3 den = 1.0 + c3 * lin_pow;
    return pow(abs(num / den), m2);
}

float linear_to_pq_scalar(float lin) 
{
    float lin_pow = pow(abs(max(lin, 0.0)), m1);
    float num = c1 + c2 * lin_pow;
    float den = 1.0 + c3 * lin_pow;
    return pow(abs(num / den), m2);
}

// =========================================================================
// TEXTURES & SAMPLERS
// =========================================================================

// The packed 8-bit RGB PNG containing 16-bit math data. X = Target PQ Luma, Y = APL.
texture TexCorrectionLUT < source = "EOTF_Correction_LUT.png"; > { Width = 1024; Height = 1024; Format = RGBA8; SRGB = false; };
sampler SamplerLUT { Texture = TexCorrectionLUT; MinFilter = LINEAR; MagFilter = LINEAR; AddressU = CLAMP; AddressV = CLAMP; };

// Full-resolution PQ Luma texture with a FULL MipMap chain for hardware downsampling
texture TexPostPQLuma { Width = 1024; Height = 1024; Format = RGBA8; MipLevels = 11; };
sampler SamplerPostPQLuma { Texture = TexPostPQLuma; MinFilter = LINEAR; MagFilter = LINEAR; MipFilter = LINEAR; };

// 1x1 texture holding the final calculated APL for the next frame
texture TexAPL { Width = 1; Height = 1; Format = R16F; };
sampler SamplerAPL { Texture = TexAPL; MinFilter = POINT; MagFilter = POINT; };

// =========================================================================
// SHADER PASSES
// =========================================================================

// PASS 1: Apply Correction (Preserving Chromaticity via Linear Ratio)
void PS_ApplyCorrection(float4 pos : SV_Position, float2 texcoord : TEXCOORD, out float4 output : SV_Target)
{
    float4 color = tex2D(ReShade::BackBuffer, texcoord);
    float prev_apl = tex2D(SamplerAPL, float2(0.5, 0.5)).r;
    float4 final_color;
    
    if (APLInputMode == 1) // PQ Decoded Normalized (HDR10)
    {
        // 1. PQ RGB to Linear RGB
        float3 lin_rgb = pq_to_linear(color.rgb);
        
        // 2. Calculate Linear Luma using Rec.2020 primaries
        float lin_luma = dot(lin_rgb, float3(0.2627, 0.6780, 0.0593));
        
        // 3. Convert Linear Luma to PQ Luma
        float pq_luma = linear_to_pq_scalar(lin_luma);
        
        // 4. Sample and Unpack the 16-bit LUT from Red/Green 8-bit channels
        float2 packed_luma = tex2D(SamplerLUT, float2(pq_luma, prev_apl)).rg;
        float corrected_pq_luma = packed_luma.r * (65280.0 / 65535.0) + packed_luma.g * (255.0 / 65535.0);
        
        // 5. Convert Corrected PQ Luma back to Linear Luma
        float corrected_lin_luma = pq_to_linear_scalar(corrected_pq_luma);
        
        // 6. Calculate Linear Scale Ratio
        float scale = corrected_lin_luma / max(lin_luma, 1e-8);
        
        // 7. Scale Linear RGB identically and re-encode to PQ
        float3 scaled_lin_rgb = lin_rgb * scale;
        final_color = float4(linear_to_pq(scaled_lin_rgb), color.a);
    }
    else // scRGB Normalized
    {
        // 1. Normalize scRGB to 0.0 - 1.0 scale (where 1.0 = 10,000 nits)
        float3 lin_rgb = color.rgb * (SIGNAL_REFERENCE_NITS / 10000.0);
        
        // 2. Calculate Linear Luma using Rec.709 primaries (scRGB uses sRGB gamut bounds by default)
        float lin_luma = dot(lin_rgb, float3(0.2126, 0.7152, 0.0722));
        
        // 3. Convert Linear Luma to PQ Luma for LUT Sampling
        float pq_luma = linear_to_pq_scalar(lin_luma);
        
        // 4. Sample and Unpack the 16-bit LUT from Red/Green 8-bit channels
        float2 packed_luma = tex2D(SamplerLUT, float2(pq_luma, prev_apl)).rg;
        float corrected_pq_luma = packed_luma.r * (65280.0 / 65535.0) + packed_luma.g * (255.0 / 65535.0);
        
        // 5. Convert Corrected PQ Luma back to Linear Luma
        float corrected_lin_luma = pq_to_linear_scalar(corrected_pq_luma);
        
        // 6. Calculate Linear Scale Ratio
        float scale = corrected_lin_luma / max(lin_luma, 1e-8);
        
        // 7. Scale the original scRGB values and output
        final_color = float4(color.rgb * scale, color.a);
    }
    
    // Output to screen
    if (DebugAPL)
    {
        // Displays the calculated APL value as a solid grayscale color on screen for testing
        output = float4(prev_apl.xxx, 1.0);
    }
    else
    {
        output = final_color;
    }
}

// PASS 2: Calculate Accurate PQ Luma for Downsampling
void PS_StorePQLuma(float4 pos : SV_Position, float2 texcoord : TEXCOORD, out float4 pq_luma_out : SV_Target)
{
    // FIX: Sample the corrected BackBuffer instead of a non-existent offline texture
    float4 color = tex2D(ReShade::BackBuffer, texcoord);
    float luma;
    
    if (APLInputMode == 1) // PQ Decoded Normalized (HDR10)
    {
        float3 lin_rgb = pq_to_linear(color.rgb);
        float lin_luma = dot(lin_rgb, float3(0.2627, 0.6780, 0.0593));
        luma = linear_to_pq_scalar(lin_luma);
    }
    else // scRGB Normalized
    {
        float3 lin_rgb = color.rgb * (SIGNAL_REFERENCE_NITS / 10000.0);
        float lin_luma = dot(lin_rgb, float3(0.2126, 0.7152, 0.0722));
        luma = linear_to_pq_scalar(lin_luma);
    }
    
    // Write in all channels for robust downsampling
    pq_luma_out = float4(luma, luma, luma, 1.0);
}

// PASS 3: Calculate Frame APL (Hardware MipMap collapse)
void PS_CalculateAPL(float4 pos : SV_Position, float2 texcoord : TEXCOORD, out float apl_out : SV_Target)
{
    // Sample the exact 1x1 hardware box-filtered mip level (Level 10) of our 1024x1024 texture
    apl_out = tex2Dlod(SamplerPostPQLuma, float4(0.5, 0.5, 0, 10.0)).r;
}

// =========================================================================
// TECHNIQUES
// =========================================================================

technique QDOLED_Fix
{
    pass ApplyCorrection
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_ApplyCorrection;
    }
    
    pass StorePQLuma
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_StorePQLuma;
        RenderTarget = TexPostPQLuma;
        GenerateMipMaps = true;
    }
    
    pass CalculateAPL
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_CalculateAPL;
        RenderTarget = TexAPL;
    }
}