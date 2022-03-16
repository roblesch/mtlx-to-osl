#version 400

struct BSDF { vec3 response; vec3 throughput; float thickness; float ior; };
#define EDF vec3
struct surfaceshader { vec3 color; vec3 transparency; };
struct volumeshader { vec3 color; vec3 transparency; };
struct displacementshader { vec3 offset; float scale; };
struct lightshader { vec3 intensity; vec3 direction; };

// Uniform block: PublicUniforms
uniform float base = 1.000000;
uniform vec3 base_color = vec3(0.944000, 0.776000, 0.373000);
uniform float diffuse_roughness = 0.000000;
uniform float metalness = 1.000000;
uniform float specular = 1.000000;
uniform vec3 specular_color = vec3(0.998000, 0.981000, 0.751000);
uniform float specular_roughness = 0.020000;
uniform float specular_IOR = 1.500000;
uniform float specular_anisotropy = 0.000000;
uniform float specular_rotation = 0.000000;
uniform float transmission = 0.000000;
uniform vec3 transmission_color = vec3(1.000000, 1.000000, 1.000000);
uniform float transmission_depth = 0.000000;
uniform vec3 transmission_scatter = vec3(0.000000, 0.000000, 0.000000);
uniform float transmission_scatter_anisotropy = 0.000000;
uniform float transmission_dispersion = 0.000000;
uniform float transmission_extra_roughness = 0.000000;
uniform float subsurface = 0.000000;
uniform vec3 subsurface_color = vec3(1.000000, 1.000000, 1.000000);
uniform vec3 subsurface_radius = vec3(1.000000, 1.000000, 1.000000);
uniform float subsurface_scale = 1.000000;
uniform float subsurface_anisotropy = 0.000000;
uniform float sheen = 0.000000;
uniform vec3 sheen_color = vec3(1.000000, 1.000000, 1.000000);
uniform float sheen_roughness = 0.300000;
uniform float coat = 0.000000;
uniform vec3 coat_color = vec3(1.000000, 1.000000, 1.000000);
uniform float coat_roughness = 0.100000;
uniform float coat_anisotropy = 0.000000;
uniform float coat_rotation = 0.000000;
uniform float coat_IOR = 1.500000;
uniform float coat_affect_color = 0.000000;
uniform float coat_affect_roughness = 0.000000;
uniform float thin_film_thickness = 0.000000;
uniform float thin_film_IOR = 1.500000;
uniform float emission = 0.000000;
uniform vec3 emission_color = vec3(1.000000, 1.000000, 1.000000);
uniform vec3 opacity = vec3(1.000000, 1.000000, 1.000000);
uniform bool thin_walled = false;

// Uniform block: PrivateUniforms
uniform mat4 u_envMatrix = mat4(-1.000000, 0.000000, 0.000000, 0.000000, 0.000000, 1.000000, 0.000000, 0.000000, 0.000000, 0.000000, -1.000000, 0.000000, 0.000000, 0.000000, 0.000000, 1.000000);
uniform sampler2D u_envRadiance;
uniform int u_envRadianceMips = 1;
uniform int u_envRadianceSamples = 16;
uniform sampler2D u_envIrradiance;
uniform vec3 u_viewPosition = vec3(0.0);
uniform int u_numActiveLightSources = 0;

in VertexData
{
    vec3 normalWorld;
    vec3 tangentWorld;
    vec3 positionWorld;
} vd;

// Pixel shader outputs
out vec4 out1;

#define M_FLOAT_EPS 1e-8

float mx_square(float x)
{
    return x*x;
}

vec2 mx_square(vec2 x)
{
    return x*x;
}

vec3 mx_square(vec3 x)
{
    return x*x;
}

#define DIRECTIONAL_ALBEDO_METHOD 0

#define MAX_LIGHT_SOURCES 3
#define M_PI 3.1415926535897932
#define M_PI_INV (1.0 / M_PI)

float mx_pow5(float x)
{
    return mx_square(mx_square(x)) * x;
}

// Standard Schlick Fresnel
float mx_fresnel_schlick(float cosTheta, float F0)
{
    float x = clamp(1.0 - cosTheta, 0.0, 1.0);
    float x5 = mx_pow5(x);
    return F0 + (1.0 - F0) * x5;
}
vec3 mx_fresnel_schlick(float cosTheta, vec3 F0)
{
    float x = clamp(1.0 - cosTheta, 0.0, 1.0);
    float x5 = mx_pow5(x);
    return F0 + (1.0 - F0) * x5;
}

// Generalized Schlick Fresnel
float mx_fresnel_schlick(float cosTheta, float F0, float F90)
{
    float x = clamp(1.0 - cosTheta, 0.0, 1.0);
    float x5 = mx_pow5(x);
    return mix(F0, F90, x5);
}
vec3 mx_fresnel_schlick(float cosTheta, vec3 F0, vec3 F90)
{
    float x = clamp(1.0 - cosTheta, 0.0, 1.0);
    float x5 = mx_pow5(x);
    return mix(F0, F90, x5);
}

// Generalized Schlick Fresnel with a variable exponent
float mx_fresnel_schlick(float cosTheta, float F0, float F90, float exponent)
{
    float x = clamp(1.0 - cosTheta, 0.0, 1.0);
    return mix(F0, F90, pow(x, exponent));
}
vec3 mx_fresnel_schlick(float cosTheta, vec3 F0, vec3 F90, float exponent)
{
    float x = clamp(1.0 - cosTheta, 0.0, 1.0);
    return mix(F0, F90, pow(x, exponent));
}

// Enforce that the given normal is forward-facing from the specified view direction.
vec3 mx_forward_facing_normal(vec3 N, vec3 V)
{
    return (dot(N, V) < 0.0) ? -N : N;
}

// https://www.graphics.rwth-aachen.de/publication/2/jgt.pdf
float mx_golden_ratio_sequence(int i)
{
    const float GOLDEN_RATIO = 1.6180339887498948;
    return fract((float(i) + 1.0) * GOLDEN_RATIO);
}

// https://people.irisa.fr/Ricardo.Marques/articles/2013/SF_CGF.pdf
vec2 mx_spherical_fibonacci(int i, int numSamples)
{
    return vec2((float(i) + 0.5) / float(numSamples), mx_golden_ratio_sequence(i));
}

// Generate a uniform-weighted sample in the unit hemisphere.
vec3 mx_uniform_sample_hemisphere(vec2 Xi)
{
    float phi = 2.0 * M_PI * Xi.x;
    float cosTheta = 1.0 - Xi.y;
    float sinTheta = sqrt(1.0 - mx_square(cosTheta));
    return vec3(cos(phi) * sinTheta,
                sin(phi) * sinTheta,
                cosTheta);
}

// Fresnel model options.
const int FRESNEL_MODEL_DIELECTRIC = 0;
const int FRESNEL_MODEL_CONDUCTOR = 1;
const int FRESNEL_MODEL_SCHLICK = 2;
const int FRESNEL_MODEL_AIRY = 3;

// XYZ to CIE 1931 RGB color space (using neutral E illuminant)
const mat3 XYZ_TO_RGB = mat3(2.3706743, -0.5138850, 0.0052982, -0.9000405, 1.4253036, -0.0146949, -0.4706338, 0.0885814, 1.0093968);

// Parameters for Fresnel calculations.
struct FresnelData
{
    int model;

    // Physical Fresnel
    vec3 ior;
    vec3 extinction;

    // Generalized Schlick Fresnel
    vec3 F0;
    vec3 F90;
    float exponent;

    // Thin film
    float tf_thickness;
    float tf_ior;
};

// https://media.disneyanimation.com/uploads/production/publication_asset/48/asset/s2012_pbs_disney_brdf_notes_v3.pdf
// Appendix B.2 Equation 13
float mx_ggx_NDF(vec3 H, vec2 alpha)
{
    vec2 He = H.xy / alpha;
    float denom = dot(He, He) + mx_square(H.z);
    return 1.0 / (M_PI * alpha.x * alpha.y * mx_square(denom));
}

// https://media.disneyanimation.com/uploads/production/publication_asset/48/asset/s2012_pbs_disney_brdf_notes_v3.pdf
// Appendix B.1 Equation 3
float mx_ggx_PDF(vec3 H, float LdotH, vec2 alpha)
{
    float NdotH = H.z;
    return mx_ggx_NDF(H, alpha) * NdotH / (4.0 * LdotH);
}

// https://media.disneyanimation.com/uploads/production/publication_asset/48/asset/s2012_pbs_disney_brdf_notes_v3.pdf
// Appendix B.2 Equation 15
vec3 mx_ggx_importance_sample_NDF(vec2 Xi, vec2 alpha)
{
    float phi = 2.0 * M_PI * Xi.x;
    float tanTheta = sqrt(Xi.y / (1.0 - Xi.y));
    vec3 H = vec3(tanTheta * alpha.x * cos(phi),
                  tanTheta * alpha.y * sin(phi),
                  1.0);
    return normalize(H);
}

// http://jcgt.org/published/0007/04/01/paper.pdf
// Appendix A Listing 1
vec3 mx_ggx_importance_sample_VNDF(vec2 Xi, vec3 V, vec2 alpha)
{
    // Transform the view direction to the hemisphere configuration.
    V = normalize(vec3(V.xy * alpha, V.z));

    // Construct an orthonormal basis from the view direction.
    float len = length(V.xy);
    vec3 T1 = (len > 0.0) ? vec3(-V.y, V.x, 0.0) / len : vec3(1.0, 0.0, 0.0);
    vec3 T2 = cross(V, T1);

    // Parameterization of the projected area.
    float r = sqrt(Xi.y);
    float phi = 2.0 * M_PI * Xi.x;
    float t1 = r * cos(phi);
    float t2 = r * sin(phi);
    float s = 0.5 * (1.0 + V.z);
    t2 = (1.0 - s) * sqrt(1.0 - mx_square(t1)) + s * t2;

    // Reprojection onto hemisphere.
    vec3 H = t1 * T1 + t2 * T2 + sqrt(max(0.0, 1.0 - mx_square(t1) - mx_square(t2))) * V;

    // Transform the microfacet normal back to the ellipsoid configuration.
    H = normalize(vec3(H.xy * alpha, max(H.z, 0.0)));

    return H;
}

// https://www.cs.cornell.edu/~srm/publications/EGSR07-btdf.pdf
// Equation 34
float mx_ggx_smith_G1(float cosTheta, float alpha)
{
    float cosTheta2 = mx_square(cosTheta);
    float tanTheta2 = (1.0 - cosTheta2) / cosTheta2;
    return 2.0 / (1.0 + sqrt(1.0 + mx_square(alpha) * tanTheta2));
}

// Height-correlated Smith masking-shadowing
// http://jcgt.org/published/0003/02/03/paper.pdf
// Equations 72 and 99
float mx_ggx_smith_G2(float NdotL, float NdotV, float alpha)
{
    float alpha2 = mx_square(alpha);
    float lambdaL = sqrt(alpha2 + (1.0 - alpha2) * mx_square(NdotL));
    float lambdaV = sqrt(alpha2 + (1.0 - alpha2) * mx_square(NdotV));
    return 2.0 / (lambdaL / NdotL + lambdaV / NdotV);
}

// Rational quadratic fit to Monte Carlo data for GGX directional albedo.
vec3 mx_ggx_dir_albedo_analytic(float NdotV, float alpha, vec3 F0, vec3 F90)
{
    float x = NdotV;
    float y = alpha;
    float x2 = mx_square(x);
    float y2 = mx_square(y);
    vec4 r = vec4(0.1003, 0.9345, 1.0, 1.0) +
             vec4(-0.6303, -2.323, -1.765, 0.2281) * x +
             vec4(9.748, 2.229, 8.263, 15.94) * y +
             vec4(-2.038, -3.748, 11.53, -55.83) * x * y +
             vec4(29.34, 1.424, 28.96, 13.08) * x2 +
             vec4(-8.245, -0.7684, -7.507, 41.26) * y2 +
             vec4(-26.44, 1.436, -36.11, 54.9) * x2 * y +
             vec4(19.99, 0.2913, 15.86, 300.2) * x * y2 +
             vec4(-5.448, 0.6286, 33.37, -285.1) * x2 * y2;
    vec2 AB = clamp(r.xy / r.zw, 0.0, 1.0);
    return F0 * AB.x + F90 * AB.y;
}

vec3 mx_ggx_dir_albedo_table_lookup(float NdotV, float alpha, vec3 F0, vec3 F90)
{
#if DIRECTIONAL_ALBEDO_METHOD == 1
    if (textureSize(u_albedoTable, 0).x > 1)
    {
        vec2 AB = texture(u_albedoTable, vec2(NdotV, alpha)).rg;
        return F0 * AB.x + F90 * AB.y;
    }
#endif
    return vec3(0.0);
}

// https://cdn2.unrealengine.com/Resources/files/2013SiggraphPresentationsNotes-26915738.pdf
vec3 mx_ggx_dir_albedo_monte_carlo(float NdotV, float alpha, vec3 F0, vec3 F90)
{
    NdotV = clamp(NdotV, M_FLOAT_EPS, 1.0);
    vec3 V = vec3(sqrt(1.0 - mx_square(NdotV)), 0, NdotV);

    vec2 AB = vec2(0.0);
    const int SAMPLE_COUNT = 64;
    for (int i = 0; i < SAMPLE_COUNT; i++)
    {
        vec2 Xi = mx_spherical_fibonacci(i, SAMPLE_COUNT);

        // Compute the half vector and incoming light direction.
        vec3 H = mx_ggx_importance_sample_VNDF(Xi, V, vec2(alpha));
        vec3 L = -reflect(V, H);
        
        // Compute dot products for this sample.
        float NdotL = clamp(L.z, M_FLOAT_EPS, 1.0);
        float VdotH = clamp(dot(V, H), M_FLOAT_EPS, 1.0);

        // Compute the Fresnel term.
        float Fc = mx_fresnel_schlick(VdotH, 0.0, 1.0);

        // Compute the per-sample geometric term.
        // https://hal.inria.fr/hal-00996995v2/document, Algorithm 2
        float G2 = mx_ggx_smith_G2(NdotL, NdotV, alpha);
        
        // Add the contribution of this sample.
        AB += vec2(G2 * (1.0 - Fc), G2 * Fc);
    }

    // Apply the global component of the geometric term and normalize.
    AB /= mx_ggx_smith_G1(NdotV, alpha) * float(SAMPLE_COUNT);

    // Return the final directional albedo.
    return F0 * AB.x + F90 * AB.y;
}

vec3 mx_ggx_dir_albedo(float NdotV, float alpha, vec3 F0, vec3 F90)
{
#if DIRECTIONAL_ALBEDO_METHOD == 0
    return mx_ggx_dir_albedo_analytic(NdotV, alpha, F0, F90);
#elif DIRECTIONAL_ALBEDO_METHOD == 1
    return mx_ggx_dir_albedo_table_lookup(NdotV, alpha, F0, F90);
#else
    return mx_ggx_dir_albedo_monte_carlo(NdotV, alpha, F0, F90);
#endif
}

float mx_ggx_dir_albedo(float NdotV, float alpha, float F0, float F90)
{
    return mx_ggx_dir_albedo(NdotV, alpha, vec3(F0), vec3(F90)).x;
}

// https://blog.selfshadow.com/publications/turquin/ms_comp_final.pdf
// Equations 14 and 16
vec3 mx_ggx_energy_compensation(float NdotV, float alpha, vec3 Fss)
{
    float Ess = mx_ggx_dir_albedo(NdotV, alpha, 1.0, 1.0);
    return 1.0 + Fss * (1.0 - Ess) / Ess;
}

float mx_ggx_energy_compensation(float NdotV, float alpha, float Fss)
{
    return mx_ggx_energy_compensation(NdotV, alpha, vec3(Fss)).x;
}

// Compute the average of an anisotropic alpha pair.
float mx_average_alpha(vec2 alpha)
{
    return sqrt(alpha.x * alpha.y);
}

// Convert a real-valued index of refraction to normal-incidence reflectivity.
float mx_ior_to_f0(float ior)
{
    return mx_square((ior - 1.0) / (ior + 1.0));
}

// https://seblagarde.wordpress.com/2013/04/29/memo-on-fresnel-equations/
float mx_fresnel_dielectric(float cosTheta, float ior)
{
    if (cosTheta < 0.0)
        return 1.0;

    float g =  ior*ior + cosTheta*cosTheta - 1.0;
    // Check for total internal reflection
    if (g < 0.0)
        return 1.0;

    g = sqrt(g);
    float gmc = g - cosTheta;
    float gpc = g + cosTheta;
    float x = gmc / gpc;
    float y = (gpc * cosTheta - 1.0) / (gmc * cosTheta + 1.0);
    return 0.5 * x * x * (1.0 + y * y);
}

// https://seblagarde.wordpress.com/2013/04/29/memo-on-fresnel-equations/
vec3 mx_fresnel_conductor(float cosTheta, vec3 n, vec3 k)
{
    cosTheta = clamp(cosTheta, 0.0, 1.0);
    float cosTheta2 = cosTheta * cosTheta;
    float sinTheta2 = 1.0 - cosTheta2;
    vec3 n2 = n * n;
    vec3 k2 = k * k;

    vec3 t0 = n2 - k2 - sinTheta2;
    vec3 a2plusb2 = sqrt(t0 * t0 + 4.0 * n2 * k2);
    vec3 t1 = a2plusb2 + cosTheta2;
    vec3 a = sqrt(max(0.5 * (a2plusb2 + t0), 0.0));
    vec3 t2 = 2.0 * a * cosTheta;
    vec3 rs = (t1 - t2) / (t1 + t2);

    vec3 t3 = cosTheta2 * a2plusb2 + sinTheta2 * sinTheta2;
    vec3 t4 = t2 * sinTheta2;
    vec3 rp = rs * (t3 - t4) / (t3 + t4);

    return 0.5 * (rp + rs);
}

// Fresnel for dielectric/dielectric interface and polarized light.
void mx_fresnel_dielectric_polarized(float cosTheta, float n1, float n2, out vec2 F, out vec2 phi)
{
    float eta2 = mx_square(n1 / n2);
    float st2 = 1.0 - cosTheta*cosTheta;

    // Check for total internal reflection
    if(eta2*st2 > 1.0)
    {
        F = vec2(1.0);
        float s = sqrt(st2 - 1.0/eta2) / cosTheta;
        phi = 2.0 * atan(vec2(-eta2 * s, -s));
        return;
    }

    float cosTheta_t = sqrt(1.0 - eta2 * st2);
    vec2 r = vec2((n2*cosTheta - n1*cosTheta_t) / (n2*cosTheta + n1*cosTheta_t),
                  (n1*cosTheta - n2*cosTheta_t) / (n1*cosTheta + n2*cosTheta_t));
    F = mx_square(r);
    phi.x = (r.x < 0.0) ? M_PI : 0.0;
    phi.y = (r.y < 0.0) ? M_PI : 0.0;
}

// Fresnel for dielectric/conductor interface and polarized light.
// TODO: Optimize this functions and support wavelength dependent complex refraction index.
void mx_fresnel_conductor_polarized(float cosTheta, float n1, float n2, float k, out vec2 F, out vec2 phi)
{
    if (k == 0.0)
    {
        // Use dielectric formula to avoid numerical issues
        mx_fresnel_dielectric_polarized(cosTheta, n1, n2, F, phi);
        return;
    }

    float A = mx_square(n2) * (1.0 - mx_square(k)) - mx_square(n1) * (1.0 - mx_square(cosTheta));
    float B = sqrt(mx_square(A) + mx_square(2.0 * mx_square(n2) * k));
    float U = sqrt((A+B) / 2.0);
    float V = sqrt((B-A) / 2.0);

    F.y = (mx_square(n1*cosTheta - U) + mx_square(V)) / (mx_square(n1*cosTheta + U) + mx_square(V));
    phi.y = atan(2.0*n1 * V*cosTheta, mx_square(U) + mx_square(V) - mx_square(n1*cosTheta)) + M_PI;

    F.x = (mx_square(mx_square(n2) * (1.0 - mx_square(k)) * cosTheta - n1*U) + mx_square(2.0 * mx_square(n2) * k * cosTheta - n1*V)) /
            (mx_square(mx_square(n2) * (1.0 - mx_square(k)) * cosTheta + n1*U) + mx_square(2.0 * mx_square(n2) * k * cosTheta + n1*V));
    phi.x = atan(2.0 * n1 * mx_square(n2) * cosTheta * (2.0*k*U - (1.0 - mx_square(k)) * V), mx_square(mx_square(n2) * (1.0 + mx_square(k)) * cosTheta) - mx_square(n1) * (mx_square(U) + mx_square(V)));
}

// Depolarization functions for natural light
float mx_depolarize(vec2 v)
{
    return 0.5 * (v.x + v.y);
}
vec3 mx_depolarize(vec3 s, vec3 p)
{
    return 0.5 * (s + p);
}

// Evaluation XYZ sensitivity curves in Fourier space
vec3 mx_eval_sensitivity(float opd, float shift)
{
    // Use Gaussian fits, given by 3 parameters: val, pos and var
    float phase = 2.0*M_PI * opd;
    vec3 val = vec3(5.4856e-13, 4.4201e-13, 5.2481e-13);
    vec3 pos = vec3(1.6810e+06, 1.7953e+06, 2.2084e+06);
    vec3 var = vec3(4.3278e+09, 9.3046e+09, 6.6121e+09);
    vec3 xyz = val * sqrt(2.0*M_PI * var) * cos(pos * phase + shift) * exp(- var * phase*phase);
    xyz.x   += 9.7470e-14 * sqrt(2.0*M_PI * 4.5282e+09) * cos(2.2399e+06 * phase + shift) * exp(- 4.5282e+09 * phase*phase);
    return xyz / 1.0685e-7;
}

// A Practical Extension to Microfacet Theory for the Modeling of Varying Iridescence
// https://belcour.github.io/blog/research/2017/05/01/brdf-thin-film.html
vec3 mx_fresnel_airy(float cosTheta, vec3 ior, vec3 extinction, float tf_thickness, float tf_ior)
{
    // Convert nm -> m
    float d = tf_thickness * 1.0e-9;

    // Assume vacuum on the outside
    float eta1 = 1.0;
    float eta2 = tf_ior;

    // Optical path difference
    float cosTheta2 = sqrt(1.0 - mx_square(eta1/eta2) * (1.0 - mx_square(cosTheta)));
    float D = 2.0 * eta2 * d * cosTheta2;

    // First interface
    vec2 R12, phi12;
    mx_fresnel_dielectric_polarized(cosTheta, eta1, eta2, R12, phi12);
    vec2 R21  = R12;
    vec2 T121 = vec2(1.0) - R12;
    vec2 phi21 = vec2(M_PI) - phi12;

    // Second interface
    vec2 R23, phi23;
    mx_fresnel_conductor_polarized(cosTheta2, eta2, ior.x, extinction.x, R23, phi23);

    // Phase shift
    vec2 phi2 = phi21 + phi23;

    // Compound terms
    vec3 R = vec3(0.0);
    vec2 R123 = R12*R23;
    vec2 r123 = sqrt(R123);
    vec2 Rs   = mx_square(T121)*R23 / (1.0-R123);

    // Reflectance term for m=0 (DC term amplitude)
    vec2 C0 = R12 + Rs;
    vec3 S0 = mx_eval_sensitivity(0.0, 0.0);
    R += mx_depolarize(C0) * S0;

    // Reflectance term for m>0 (pairs of diracs)
    vec2 Cm = Rs - T121;
    for (int m=1; m<=3; ++m)
    {
        Cm *= r123;
        vec3 SmS = 2.0 * mx_eval_sensitivity(float(m)*D, float(m)*phi2.x);
        vec3 SmP = 2.0 * mx_eval_sensitivity(float(m)*D, float(m)*phi2.y);
        R += mx_depolarize(Cm.x*SmS, Cm.y*SmP);
    }

    // Convert back to RGB reflectance
    R = clamp(XYZ_TO_RGB * R, vec3(0.0), vec3(1.0));

    return R;
}

FresnelData mx_init_fresnel_data(int model)
{
    return FresnelData(model, vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), 0.0, 0.0, 0.0);
}

FresnelData mx_init_fresnel_dielectric(float ior)
{
    FresnelData fd = mx_init_fresnel_data(FRESNEL_MODEL_DIELECTRIC);
    fd.ior = vec3(ior);
    return fd;
}

FresnelData mx_init_fresnel_conductor(vec3 ior, vec3 extinction)
{
    FresnelData fd = mx_init_fresnel_data(FRESNEL_MODEL_CONDUCTOR);
    fd.ior = ior;
    fd.extinction = extinction;
    return fd;
}

FresnelData mx_init_fresnel_schlick(vec3 F0)
{
    FresnelData fd = mx_init_fresnel_data(FRESNEL_MODEL_SCHLICK);
    fd.F0 = F0;
    fd.F90 = vec3(1.0);
    fd.exponent = 5.0f;
    return fd;
}

FresnelData mx_init_fresnel_schlick(vec3 F0, vec3 F90, float exponent)
{
    FresnelData fd = mx_init_fresnel_data(FRESNEL_MODEL_SCHLICK);
    fd.F0 = F0;
    fd.F90 = F90;
    fd.exponent = exponent;
    return fd;
}

FresnelData mx_init_fresnel_dielectric_airy(float ior, float tf_thickness, float tf_ior)
{
    FresnelData fd = mx_init_fresnel_data(FRESNEL_MODEL_AIRY);
    fd.ior = vec3(ior);
    fd.tf_thickness = tf_thickness;
    fd.tf_ior = tf_ior;
    return fd;
}

FresnelData mx_init_fresnel_conductor_airy(vec3 ior, vec3 extinction, float tf_thickness, float tf_ior)
{
    FresnelData fd = mx_init_fresnel_data(FRESNEL_MODEL_AIRY);
    fd.ior = ior;
    fd.extinction = extinction;
    fd.tf_thickness = tf_thickness;
    fd.tf_ior = tf_ior;
    return fd;
}

vec3 mx_compute_fresnel(float cosTheta, FresnelData fd)
{
    if (fd.model == FRESNEL_MODEL_DIELECTRIC)
    {
        return vec3(mx_fresnel_dielectric(cosTheta, fd.ior.x));
    }
    else if (fd.model == FRESNEL_MODEL_CONDUCTOR)
    {
        return mx_fresnel_conductor(cosTheta, fd.ior, fd.extinction);
    }
    else if (fd.model == FRESNEL_MODEL_SCHLICK)
    {
        return mx_fresnel_schlick(cosTheta, fd.F0, fd.F90, fd.exponent);
    }
    else
    {
        return mx_fresnel_airy(cosTheta, fd.ior, fd.extinction, fd.tf_thickness, fd.tf_ior);
    }
}

vec2 mx_latlong_projection(vec3 dir)
{
    float latitude = -asin(dir.y) * M_PI_INV + 0.5;
    float longitude = atan(dir.x, -dir.z) * M_PI_INV * 0.5 + 0.5;
    return vec2(longitude, latitude);
}

vec3 mx_latlong_map_lookup(vec3 dir, mat4 transform, float lod, sampler2D envSampler)
{
    vec3 envDir = normalize((transform * vec4(dir,0.0)).xyz);
    vec2 uv = mx_latlong_projection(envDir);
    return textureLod(envSampler, uv, lod).rgb;
}

// https://developer.nvidia.com/gpugems/GPUGems3/gpugems3_ch20.html
// Section 20.4 Equation 13
float mx_latlong_compute_lod(vec3 dir, float pdf, float maxMipLevel, int envSamples)
{
    const float MIP_LEVEL_OFFSET = 1.5;
    float effectiveMaxMipLevel = maxMipLevel - MIP_LEVEL_OFFSET;
    float distortion = sqrt(1.0 - mx_square(dir.y));
    return max(effectiveMaxMipLevel - 0.5 * log2(float(envSamples) * pdf * distortion), 0.0);
}

vec3 mx_environment_radiance(vec3 N, vec3 V, vec3 X, vec2 alpha, int distribution, FresnelData fd)
{
    // Generate tangent frame.
    vec3 Y = normalize(cross(N, X));
    X = cross(Y, N);
    mat3 tangentToWorld = mat3(X, Y, N);

    // Transform the view vector to tangent space.
    V = vec3(dot(V, X), dot(V, Y), dot(V, N));

    // Compute derived properties.
    float NdotV = clamp(V.z, M_FLOAT_EPS, 1.0);
    float avgAlpha = mx_average_alpha(alpha);
    
    // Integrate outgoing radiance using filtered importance sampling.
    // http://cgg.mff.cuni.cz/~jaroslav/papers/2008-egsr-fis/2008-egsr-fis-final-embedded.pdf
    vec3 radiance = vec3(0.0);
    int envRadianceSamples = u_envRadianceSamples;
    for (int i = 0; i < envRadianceSamples; i++)
    {
        vec2 Xi = mx_spherical_fibonacci(i, envRadianceSamples);

        // Compute the half vector and incoming light direction.
        vec3 H = mx_ggx_importance_sample_NDF(Xi, alpha);
        vec3 L = -reflect(V, H);
        
        // Compute dot products for this sample.
        float NdotH = clamp(H.z, M_FLOAT_EPS, 1.0);
        float NdotL = clamp(L.z, M_FLOAT_EPS, 1.0);
        float VdotH = clamp(dot(V, H), M_FLOAT_EPS, 1.0);
        float LdotH = VdotH;

        // Sample the environment light from the given direction.
        vec3 Lw = tangentToWorld * L;
        float pdf = mx_ggx_PDF(H, LdotH, alpha);
        float lod = mx_latlong_compute_lod(Lw, pdf, float(u_envRadianceMips - 1), envRadianceSamples);
        vec3 sampleColor = mx_latlong_map_lookup(Lw, u_envMatrix, lod, u_envRadiance);

        // Compute the Fresnel term.
        vec3 F = mx_compute_fresnel(VdotH, fd);

        // Compute the geometric term.
        float G = mx_ggx_smith_G2(NdotL, NdotV, avgAlpha);

        // Add the radiance contribution of this sample.
        // From https://cdn2.unrealengine.com/Resources/files/2013SiggraphPresentationsNotes-26915738.pdf
        //   incidentLight = sampleColor * NdotL
        //   microfacetSpecular = D * F * G / (4 * NdotL * NdotV)
        //   pdf = D * NdotH / (4 * VdotH)
        //   radiance = incidentLight * microfacetSpecular / pdf
        radiance += sampleColor * F * G * VdotH / (NdotV * NdotH);
    }

    // Normalize and return the final radiance.
    radiance /= float(envRadianceSamples);
    return radiance;
}

vec3 mx_environment_irradiance(vec3 N)
{
    return mx_latlong_map_lookup(N, u_envMatrix, 0.0, u_envIrradiance);
}

struct LightData
{
    int type;
};

uniform LightData u_lightData[MAX_LIGHT_SOURCES];

int numActiveLightSources()
{
    return min(u_numActiveLightSources, MAX_LIGHT_SOURCES) ;
}

void sampleLightSource(LightData light, vec3 position, out lightshader result)
{
    result.intensity = vec3(0.0);
    result.direction = vec3(0.0);
}

void mx_roughness_anisotropy(float roughness, float anisotropy, out vec2 result)
{
    float roughness_sqr = clamp(roughness*roughness, M_FLOAT_EPS, 1.0);
    if (anisotropy > 0.0)
    {
        float aspect = sqrt(1.0 - clamp(anisotropy, 0.0, 0.98));
        result.x = min(roughness_sqr / aspect, 1.0);
        result.y = roughness_sqr * aspect;
    }
    else
    {
        result.x = roughness_sqr;
        result.y = roughness_sqr;
    }
}


// http://www.aconty.com/pdf/s2017_pbs_imageworks_sheen.pdf
// Equation 2
float mx_imageworks_sheen_NDF(float NdotH, float roughness)
{
    float invRoughness = 1.0 / max(roughness, 0.005);
    float cos2 = NdotH * NdotH;
    float sin2 = 1.0 - cos2;
    return (2.0 + invRoughness) * pow(sin2, invRoughness * 0.5) / (2.0 * M_PI);
}

float mx_imageworks_sheen_brdf(float NdotL, float NdotV, float NdotH, float roughness)
{
    // Microfacet distribution.
    float D = mx_imageworks_sheen_NDF(NdotH, roughness);

    // Fresnel and geometry terms are ignored.
    float F = 1.0;
    float G = 1.0;

    // We use a smoother denominator, as in:
    // https://blog.selfshadow.com/publications/s2013-shading-course/rad/s2013_pbs_rad_notes.pdf
    return D * F * G / (4.0 * (NdotL + NdotV - NdotL*NdotV));
}

// Rational quadratic fit to Monte Carlo data for Imageworks sheen directional albedo.
float mx_imageworks_sheen_dir_albedo_analytic(float NdotV, float roughness)
{
    vec2 r = vec2(13.67300, 1.0) +
             vec2(-68.78018, 61.57746) * NdotV +
             vec2(799.08825, 442.78211) * roughness +
             vec2(-905.00061, 2597.49308) * NdotV * roughness +
             vec2(60.28956, 121.81241) * mx_square(NdotV) +
             vec2(1086.96473, 3045.55075) * mx_square(roughness);
    return r.x / r.y;
}

float mx_imageworks_sheen_dir_albedo_table_lookup(float NdotV, float roughness)
{
#if DIRECTIONAL_ALBEDO_METHOD == 1
    if (textureSize(u_albedoTable, 0).x > 1)
    {
        return texture(u_albedoTable, vec2(NdotV, roughness)).b;
    }
#endif
    return 0.0;
}

float mx_imageworks_sheen_dir_albedo_monte_carlo(float NdotV, float roughness)
{
    NdotV = clamp(NdotV, M_FLOAT_EPS, 1.0);
    vec3 V = vec3(sqrt(1.0f - mx_square(NdotV)), 0, NdotV);

    float radiance = 0.0;
    const int SAMPLE_COUNT = 64;
    for (int i = 0; i < SAMPLE_COUNT; i++)
    {
        vec2 Xi = mx_spherical_fibonacci(i, SAMPLE_COUNT);

        // Compute the incoming light direction and half vector.
        vec3 L = mx_uniform_sample_hemisphere(Xi);
        vec3 H = normalize(L + V);
        
        // Compute dot products for this sample.
        float NdotL = clamp(L.z, M_FLOAT_EPS, 1.0);
        float NdotH = clamp(H.z, M_FLOAT_EPS, 1.0);

        // Compute sheen reflectance.
        float reflectance = mx_imageworks_sheen_brdf(NdotL, NdotV, NdotH, roughness);

        // Add the radiance contribution of this sample.
        //   uniform_pdf = 1 / (2 * PI)
        //   radiance = reflectance * NdotL / uniform_pdf;
        radiance += reflectance * NdotL * 2.0 * M_PI;
    }

    // Return the final directional albedo.
    return radiance / float(SAMPLE_COUNT);
}

float mx_imageworks_sheen_dir_albedo(float NdotV, float roughness)
{
#if DIRECTIONAL_ALBEDO_METHOD == 0
    float dirAlbedo = mx_imageworks_sheen_dir_albedo_analytic(NdotV, roughness);
#elif DIRECTIONAL_ALBEDO_METHOD == 1
    float dirAlbedo = mx_imageworks_sheen_dir_albedo_table_lookup(NdotV, roughness);
#else
    float dirAlbedo = mx_imageworks_sheen_dir_albedo_monte_carlo(NdotV, roughness);
#endif
    return clamp(dirAlbedo, 0.0, 1.0);
}

void mx_sheen_bsdf_reflection(vec3 L, vec3 V, vec3 P, float occlusion, float weight, vec3 color, float roughness, vec3 N, inout BSDF bsdf)
{
    if (weight < M_FLOAT_EPS)
    {
        return;
    }

    N = mx_forward_facing_normal(N, V);

    vec3 H = normalize(L + V);

    float NdotL = clamp(dot(N, L), M_FLOAT_EPS, 1.0);
    float NdotV = clamp(dot(N, V), M_FLOAT_EPS, 1.0);
    float NdotH = clamp(dot(N, H), M_FLOAT_EPS, 1.0);

    vec3 fr = color * mx_imageworks_sheen_brdf(NdotL, NdotV, NdotH, roughness);
    float dirAlbedo = mx_imageworks_sheen_dir_albedo(NdotV, roughness);
    bsdf.throughput = vec3(1.0 - dirAlbedo * weight);

    // We need to include NdotL from the light integral here
    // as in this case it's not cancelled out by the BRDF denominator.
    bsdf.response = fr * NdotL * occlusion * weight;
}

void mx_sheen_bsdf_indirect(vec3 V, float weight, vec3 color, float roughness, vec3 N, inout BSDF bsdf)
{
    if (weight < M_FLOAT_EPS)
    {
        return;
    }

    N = mx_forward_facing_normal(N, V);

    float NdotV = clamp(dot(N, V), M_FLOAT_EPS, 1.0);

    float dirAlbedo = mx_imageworks_sheen_dir_albedo(NdotV, roughness);
    bsdf.throughput = vec3(1.0 - dirAlbedo * weight);

    vec3 Li = mx_environment_irradiance(N);
    bsdf.response = Li * color * dirAlbedo * weight;
}

void mx_luminance_color3(vec3 _in, vec3 lumacoeffs, out vec3 result)
{
    result = vec3(dot(_in, lumacoeffs));
}

mat4 mx_rotationMatrix(vec3 axis, float angle)
{
    axis = normalize(axis);
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;

    return mat4(oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,  0.0,
                oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,  0.0,
                oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c,           0.0,
                0.0,                                0.0,                                0.0,                                1.0);
}

void mx_rotate_vector3(vec3 _in, float amount, vec3 axis, out vec3 result)
{
    float rotationRadians = radians(amount);
    mat4 m = mx_rotationMatrix(axis, rotationRadians);
    result = (m * vec4(_in, 1.0)).xyz;
}

void mx_artistic_ior(vec3 reflectivity, vec3 edge_color, out vec3 ior, out vec3 extinction)
{
    // "Artist Friendly Metallic Fresnel", Ole Gulbrandsen, 2014
    // http://jcgt.org/published/0003/04/03/paper.pdf

    vec3 r = clamp(reflectivity, 0.0, 0.99);
    vec3 r_sqrt = sqrt(r);
    vec3 n_min = (1.0 - r) / (1.0 + r);
    vec3 n_max = (1.0 + r_sqrt) / (1.0 - r_sqrt);
    ior = mix(n_max, n_min, edge_color);

    vec3 np1 = ior + 1.0;
    vec3 nm1 = ior - 1.0;
    vec3 k2 = (np1*np1 * r - nm1*nm1) / (1.0 - r);
    k2 = max(k2, 0.0);
    extinction = sqrt(k2);
}

void mx_uniform_edf(vec3 N, vec3 L, vec3 color, out EDF result)
{
    result = color;
}


void mx_dielectric_bsdf_reflection(vec3 L, vec3 V, vec3 P, float occlusion, float weight, vec3 tint, float ior, vec2 roughness, vec3 N, vec3 X, int distribution, int scatter_mode, inout BSDF bsdf)
{
    if (weight < M_FLOAT_EPS)
    {
        return;
    }

    N = mx_forward_facing_normal(N, V);

    vec3 Y = normalize(cross(N, X));
    vec3 H = normalize(L + V);

    float NdotL = clamp(dot(N, L), M_FLOAT_EPS, 1.0);
    float NdotV = clamp(dot(N, V), M_FLOAT_EPS, 1.0);
    float VdotH = clamp(dot(V, H), M_FLOAT_EPS, 1.0);

    vec2 safeAlpha = clamp(roughness, M_FLOAT_EPS, 1.0);
    float avgAlpha = mx_average_alpha(safeAlpha);
    vec3 Ht = vec3(dot(H, X), dot(H, Y), dot(H, N));

    FresnelData fd;
    if (bsdf.thickness > 0.0)
    { 
        fd = mx_init_fresnel_dielectric_airy(ior, bsdf.thickness, bsdf.ior);
    }
    else
    {
         fd = mx_init_fresnel_dielectric(ior);
    }
    vec3  F = mx_compute_fresnel(VdotH, fd);
    float D = mx_ggx_NDF(Ht, safeAlpha);
    float G = mx_ggx_smith_G2(NdotL, NdotV, avgAlpha);

    float F0 = mx_ior_to_f0(ior);
    vec3 comp = mx_ggx_energy_compensation(NdotV, avgAlpha, F);
    vec3 dirAlbedo = mx_ggx_dir_albedo(NdotV, avgAlpha, F0, 1.0) * comp;
    bsdf.throughput = 1.0 - dirAlbedo * weight;

    // Note: NdotL is cancelled out
    bsdf.response = D * F * G * comp * tint * occlusion * weight / (4.0 * NdotV);
}

void mx_dielectric_bsdf_transmission(vec3 V, float weight, vec3 tint, float ior, vec2 roughness, vec3 N, vec3 X, int distribution, int scatter_mode, inout BSDF bsdf)
{
    if (scatter_mode == 1)
    {
        bsdf.response = tint * weight;
        bsdf.throughput = bsdf.response;
        return;
    }

    if (weight < M_FLOAT_EPS)
    {
        return;
    }

    N = mx_forward_facing_normal(N, V);
    float NdotV = clamp(dot(N, V), M_FLOAT_EPS, 1.0);

    FresnelData fd;
    if (bsdf.thickness > 0.0)
        fd = mx_init_fresnel_dielectric_airy(ior, bsdf.thickness, bsdf.ior);
    else
        fd = mx_init_fresnel_dielectric(ior);

    vec3 F = mx_compute_fresnel(NdotV, fd);

    vec2 safeAlpha = clamp(roughness, M_FLOAT_EPS, 1.0);
    float avgAlpha = mx_average_alpha(safeAlpha);
    float F0 = mx_ior_to_f0(ior);
    vec3 comp = mx_ggx_energy_compensation(NdotV, avgAlpha, F);
    vec3 dirAlbedo = mx_ggx_dir_albedo(NdotV, avgAlpha, F0, 1.0) * comp;
    bsdf.throughput = 1.0 - dirAlbedo * weight;

    bsdf.response = (scatter_mode == 2) ? tint * weight * bsdf.throughput : vec3(0.0);
}

void mx_dielectric_bsdf_indirect(vec3 V, float weight, vec3 tint, float ior, vec2 roughness, vec3 N, vec3 X, int distribution, int scatter_mode, inout BSDF bsdf)
{
    if (weight < M_FLOAT_EPS)
    {
        return;
    }

    N = mx_forward_facing_normal(N, V);

    float NdotV = clamp(dot(N, V), M_FLOAT_EPS, 1.0);

    FresnelData fd;
    if (bsdf.thickness > 0.0)
        fd = mx_init_fresnel_dielectric_airy(ior, bsdf.thickness, bsdf.ior);
    else
        fd = mx_init_fresnel_dielectric(ior);

    vec3 F = mx_compute_fresnel(NdotV, fd);

    vec2 safeAlpha = clamp(roughness, M_FLOAT_EPS, 1.0);
    float avgAlpha = mx_average_alpha(safeAlpha);
    float F0 = mx_ior_to_f0(ior);
    vec3 comp = mx_ggx_energy_compensation(NdotV, avgAlpha, F);
    vec3 dirAlbedo = mx_ggx_dir_albedo(NdotV, avgAlpha, F0, 1.0) * comp;
    bsdf.throughput = 1.0 - dirAlbedo * weight;

    vec3 Li = mx_environment_radiance(N, V, X, safeAlpha, distribution, fd);
    bsdf.response = Li * tint * comp * weight;
}


void mx_conductor_bsdf_reflection(vec3 L, vec3 V, vec3 P, float occlusion, float weight, vec3 ior_n, vec3 ior_k, vec2 roughness, vec3 N, vec3 X, int distribution, inout BSDF bsdf)
{
    bsdf.throughput = vec3(0.0);

    if (weight < M_FLOAT_EPS)
    {
        return;
    }

    N = mx_forward_facing_normal(N, V);

    vec3 Y = normalize(cross(N, X));
    vec3 H = normalize(L + V);

    float NdotL = clamp(dot(N, L), M_FLOAT_EPS, 1.0);
    float NdotV = clamp(dot(N, V), M_FLOAT_EPS, 1.0);
    float VdotH = clamp(dot(V, H), M_FLOAT_EPS, 1.0);

    vec2 safeAlpha = clamp(roughness, M_FLOAT_EPS, 1.0);
    float avgAlpha = mx_average_alpha(safeAlpha);
    vec3 Ht = vec3(dot(H, X), dot(H, Y), dot(H, N));

    FresnelData fd;
    if (bsdf.thickness > 0.0)
        fd = mx_init_fresnel_conductor_airy(ior_n, ior_k, bsdf.thickness, bsdf.ior);
    else
        fd = mx_init_fresnel_conductor(ior_n, ior_k);

    vec3 F = mx_compute_fresnel(VdotH, fd);
    float D = mx_ggx_NDF(Ht, safeAlpha);
    float G = mx_ggx_smith_G2(NdotL, NdotV, avgAlpha);

    vec3 comp = mx_ggx_energy_compensation(NdotV, avgAlpha, F);

    // Note: NdotL is cancelled out
    bsdf.response = D * F * G * comp * occlusion * weight / (4.0 * NdotV);
}

void mx_conductor_bsdf_indirect(vec3 V, float weight, vec3 ior_n, vec3 ior_k, vec2 roughness, vec3 N, vec3 X, int distribution, inout BSDF bsdf)
{
    bsdf.throughput = vec3(0.0);

    if (weight < M_FLOAT_EPS)
    {
        return;
    }

    N = mx_forward_facing_normal(N, V);

    float NdotV = clamp(dot(N, V), M_FLOAT_EPS, 1.0);

    FresnelData fd;
    if (bsdf.thickness > 0.0)
        fd = mx_init_fresnel_conductor_airy(ior_n, ior_k, bsdf.thickness, bsdf.ior);
    else
        fd = mx_init_fresnel_conductor(ior_n, ior_k);

    vec3 F = mx_compute_fresnel(NdotV, fd);

    vec2 safeAlpha = clamp(roughness, M_FLOAT_EPS, 1.0);
    float avgAlpha = mx_average_alpha(safeAlpha);
    vec3 comp = mx_ggx_energy_compensation(NdotV, avgAlpha, F);

    vec3 Li = mx_environment_radiance(N, V, X, safeAlpha, distribution, fd);

    bsdf.response = Li * comp * weight;
}

// We fake diffuse transmission by using diffuse reflection from the opposite side.
// So this BTDF is really a BRDF.
void mx_translucent_bsdf_reflection(vec3 L, vec3 V, vec3 P, float occlusion, float weight, vec3 color, vec3 normal, inout BSDF bsdf)
{
    bsdf.throughput = vec3(0.0);

    // Invert normal since we're transmitting light from the other side
    float NdotL = dot(L, -normal);
    if (NdotL <= 0.0 || weight < M_FLOAT_EPS)
    {
        return;
    }

    bsdf.response = color * weight * NdotL * M_PI_INV;
}

void mx_translucent_bsdf_indirect(vec3 V, float weight, vec3 color, vec3 normal, inout BSDF bsdf)
{
    bsdf.throughput = vec3(0.0);

    if (weight < M_FLOAT_EPS)
    {
        return;
    }

    // Invert normal since we're transmitting light from the other side
    vec3 Li = mx_environment_irradiance(-normal);
    bsdf.response = Li * color * weight;
}


// Based on the OSL implementation of Oren-Nayar diffuse, which is in turn
// based on https://mimosa-pudica.net/improved-oren-nayar.html.
float mx_oren_nayar_diffuse(vec3 L, vec3 V, vec3 N, float NdotL, float roughness)
{
    float LdotV = clamp(dot(L, V), M_FLOAT_EPS, 1.0);
    float NdotV = clamp(dot(N, V), M_FLOAT_EPS, 1.0);
    float s = LdotV - NdotL * NdotV;
    float stinv = (s > 0.0f) ? s / max(NdotL, NdotV) : 0.0;

    float sigma2 = mx_square(roughness * M_PI);
    float A = 1.0 - 0.5 * (sigma2 / (sigma2 + 0.33));
    float B = 0.45 * sigma2 / (sigma2 + 0.09);

    return A + B * stinv;
}

// https://media.disneyanimation.com/uploads/production/publication_asset/48/asset/s2012_pbs_disney_brdf_notes_v3.pdf
// Section 5.3
float mx_burley_diffuse(vec3 L, vec3 V, vec3 N, float NdotL, float roughness)
{
    vec3 H = normalize(L + V);
    float LdotH = clamp(dot(L, H), M_FLOAT_EPS, 1.0);
    float NdotV = clamp(dot(N, V), M_FLOAT_EPS, 1.0);

    float F90 = 0.5 + (2.0 * roughness * mx_square(LdotH));
    float refL = mx_fresnel_schlick(NdotL, 1.0, F90);
    float refV = mx_fresnel_schlick(NdotV, 1.0, F90);
    return refL * refV;
}

// Compute the directional albedo component of Burley diffuse for the given
// view angle and roughness.  Curve fit provided by Stephen Hill.
float mx_burley_diffuse_dir_albedo(float NdotV, float roughness)
{
    float x = NdotV;
    float fit0 = 0.97619 - 0.488095 * mx_pow5(1.0 - x);
    float fit1 = 1.55754 + (-2.02221 + (2.56283 - 1.06244 * x) * x) * x;
    return mix(fit0, fit1, roughness);
}

// Evaluate the Burley diffusion profile for the given distance and diffusion shape.
// Based on https://graphics.pixar.com/library/ApproxBSSRDF/
vec3 mx_burley_diffusion_profile(float dist, vec3 shape)
{
    vec3 num1 = exp(-shape * dist);
    vec3 num2 = exp(-shape * dist / 3.0);
    float denom = max(dist, M_FLOAT_EPS);
    return (num1 + num2) / denom;
}

// Integrate the Burley diffusion profile over a sphere of the given radius.
// Inspired by Eric Penner's presentation in http://advances.realtimerendering.com/s2011/
vec3 mx_integrate_burley_diffusion(vec3 N, vec3 L, float radius, vec3 mfp)
{
    float theta = acos(dot(N, L));

    // Estimate the Burley diffusion shape from mean free path.
    vec3 shape = vec3(1.0) / max(mfp, 0.1);

    // Integrate the profile over the sphere.
    vec3 sumD = vec3(0.0);
    vec3 sumR = vec3(0.0);
    const int SAMPLE_COUNT = 32;
    const float SAMPLE_WIDTH = (2.0 * M_PI) / float(SAMPLE_COUNT);
    for (int i = 0; i < SAMPLE_COUNT; i++)
    {
        float x = -M_PI + (float(i) + 0.5) * SAMPLE_WIDTH;
        float dist = radius * abs(2.0 * sin(x * 0.5));
        vec3 R = mx_burley_diffusion_profile(dist, shape);
        sumD += R * max(cos(theta + x), 0.0);
        sumR += R;
    }

    return sumD / sumR;
}

vec3 mx_subsurface_scattering_approx(vec3 N, vec3 L, vec3 P, vec3 albedo, vec3 mfp)
{
    float curvature = length(fwidth(N)) / length(fwidth(P));
    float radius = 1.0 / max(curvature, 0.01);
    return albedo * mx_integrate_burley_diffusion(N, L, radius, mfp) / vec3(M_PI);
}

void mx_subsurface_bsdf_reflection(vec3 L, vec3 V, vec3 P, float occlusion, float weight, vec3 color, vec3 radius, float anisotropy, vec3 normal, inout BSDF bsdf)
{
    bsdf.throughput = vec3(0.0);

    if (weight < M_FLOAT_EPS)
    {
        return;
    }

    normal = mx_forward_facing_normal(normal, V);

    vec3 sss = mx_subsurface_scattering_approx(normal, L, P, color, radius);
    float NdotL = clamp(dot(normal, L), M_FLOAT_EPS, 1.0);
    float visibleOcclusion = 1.0 - NdotL * (1.0 - occlusion);
    bsdf.response = sss * visibleOcclusion * weight;
}

void mx_subsurface_bsdf_indirect(vec3 V, float weight, vec3 color, vec3 radius, float anisotropy, vec3 normal, inout BSDF bsdf)
{
    bsdf.throughput = vec3(0.0);

    if (weight < M_FLOAT_EPS)
    {
        return;
    }

    normal = mx_forward_facing_normal(normal, V);

    // For now, we render indirect subsurface as simple indirect diffuse.
    vec3 Li = mx_environment_irradiance(normal);
    bsdf.response = Li * color * weight;
}


void mx_oren_nayar_diffuse_bsdf_reflection(vec3 L, vec3 V, vec3 P, float occlusion, float weight, vec3 color, float roughness, vec3 normal, inout BSDF bsdf)
{
    bsdf.throughput = vec3(0.0);

    if (weight < M_FLOAT_EPS)
    {
        return;
    }

    normal = mx_forward_facing_normal(normal, V);

    float NdotL = clamp(dot(normal, L), M_FLOAT_EPS, 1.0);

    bsdf.response = color * occlusion * weight * NdotL * M_PI_INV;
    if (roughness > 0.0)
    {
        bsdf.response *= mx_oren_nayar_diffuse(L, V, normal, NdotL, roughness);
    }
}

void mx_oren_nayar_diffuse_bsdf_indirect(vec3 V, float weight, vec3 color, float roughness, vec3 normal, inout BSDF bsdf)
{
    bsdf.throughput = vec3(0.0);

    if (weight < M_FLOAT_EPS)
    {
        return;
    }

    normal = mx_forward_facing_normal(normal, V);

    vec3 Li = mx_environment_irradiance(normal);
    bsdf.response = Li * color * weight;
}

void NG_standard_surface_surfaceshader_100(float base, vec3 base_color, float diffuse_roughness, float metalness, float specular, vec3 specular_color, float specular_roughness, float specular_IOR, float specular_anisotropy, float specular_rotation, float transmission, vec3 transmission_color, float transmission_depth, vec3 transmission_scatter, float transmission_scatter_anisotropy, float transmission_dispersion, float transmission_extra_roughness, float subsurface, vec3 subsurface_color, vec3 subsurface_radius, float subsurface_scale, float subsurface_anisotropy, float sheen, vec3 sheen_color, float sheen_roughness, float coat, vec3 coat_color, float coat_roughness, float coat_anisotropy, float coat_rotation, float coat_IOR, vec3 coat_normal, float coat_affect_color, float coat_affect_roughness, float thin_film_thickness, float thin_film_IOR, float emission, vec3 emission_color, vec3 opacity, bool thin_walled, vec3 normal, vec3 tangent, out surfaceshader out1)
{
    vec2 coat_roughness_vector_out = vec2(0.0);
    mx_roughness_anisotropy(coat_roughness, coat_anisotropy, coat_roughness_vector_out);
    const float coat_tangent_rotate_degree_in2_tmp = 360.000000;
    float coat_tangent_rotate_degree_out = coat_rotation * coat_tangent_rotate_degree_in2_tmp;
    vec3 metal_reflectivity_out = base_color * base;
    vec3 metal_edgecolor_out = specular_color * specular;
    float coat_affect_roughness_multiply1_out = coat_affect_roughness * coat;
    const float tangent_rotate_degree_in2_tmp = 360.000000;
    float tangent_rotate_degree_out = specular_rotation * tangent_rotate_degree_in2_tmp;
    const float coat_clamped_low_tmp = 0.000000;
    const float coat_clamped_high_tmp = 1.000000;
    float coat_clamped_out = clamp(coat, coat_clamped_low_tmp, coat_clamped_high_tmp);
    vec3 subsurface_radius_vector_out = vec3(subsurface_radius.x, subsurface_radius.y, subsurface_radius.z);
    float subsurface_selector_out = float(thin_walled);
    const vec3 coat_attenuation_bg_tmp = vec3(1.000000, 1.000000, 1.000000);
    vec3 coat_attenuation_out = mix(coat_attenuation_bg_tmp, coat_color, coat);
    vec3 emission_weight_out = emission_color * emission;
    const vec3 coat_emission_attenuation_bg_tmp = vec3(1.000000, 1.000000, 1.000000);
    vec3 coat_emission_attenuation_out = mix(coat_emission_attenuation_bg_tmp, coat_color, coat);
    vec3 opacity_luminance_out = vec3(0.0);
    mx_luminance_color3(opacity, vec3(0.272229, 0.674082, 0.053689), opacity_luminance_out);
    vec3 coat_tangent_rotate_out = vec3(0.0);
    mx_rotate_vector3(tangent, coat_tangent_rotate_degree_out, coat_normal, coat_tangent_rotate_out);
    vec3 artistic_ior_ior = vec3(0.0);
    vec3 artistic_ior_extinction = vec3(0.0);
    mx_artistic_ior(metal_reflectivity_out, metal_edgecolor_out, artistic_ior_ior, artistic_ior_extinction);
    float coat_affect_roughness_multiply2_out = coat_affect_roughness_multiply1_out * coat_roughness;
    vec3 tangent_rotate_out = vec3(0.0);
    mx_rotate_vector3(tangent, tangent_rotate_degree_out, normal, tangent_rotate_out);
    float coat_gamma_multiply_out = coat_clamped_out * coat_affect_color;
    vec3 subsurface_radius_scaled_out = subsurface_radius_vector_out * subsurface_scale;
    vec3 emission_weight_attenuated_out = emission_weight_out * coat_emission_attenuation_out;
    vec3 coat_tangent_rotate_normalize_out = normalize(coat_tangent_rotate_out);
    const float coat_affected_roughness_fg_tmp = 1.000000;
    float coat_affected_roughness_out = mix(specular_roughness, coat_affected_roughness_fg_tmp, coat_affect_roughness_multiply2_out);
    vec3 tangent_rotate_normalize_out = normalize(tangent_rotate_out);
    const float coat_gamma_in2_tmp = 1.000000;
    float coat_gamma_out = coat_gamma_multiply_out + coat_gamma_in2_tmp;
    vec3 coat_tangent_out = vec3(0.0);
    if (coat_anisotropy > 0.000000)
    {
        coat_tangent_out = coat_tangent_rotate_normalize_out;
    }
    else
    {
        coat_tangent_out = tangent;
    }
    vec2 main_roughness_out = vec2(0.0);
    mx_roughness_anisotropy(coat_affected_roughness_out, specular_anisotropy, main_roughness_out);
    vec3 main_tangent_out = vec3(0.0);
    if (specular_anisotropy > 0.000000)
    {
        main_tangent_out = tangent_rotate_normalize_out;
    }
    else
    {
        main_tangent_out = tangent;
    }
    vec3 coat_affected_subsurface_color_out = pow(subsurface_color, vec3(coat_gamma_out));
    vec3 coat_affected_diffuse_color_out = pow(base_color, vec3(coat_gamma_out));
    surfaceshader shader_constructor_out = surfaceshader(vec3(0.0),vec3(0.0));
    {
        vec3 N = normalize(vd.normalWorld);
        vec3 V = normalize(u_viewPosition - vd.positionWorld);
        vec3 P = vd.positionWorld;

        // Shadow occlusion
        float occlusion = 1.0;

        // Light loop
        int numLights = numActiveLightSources();
        lightshader lightShader;
        for (int activeLightIndex = 0; activeLightIndex < numLights; ++activeLightIndex)
        {
            sampleLightSource(u_lightData[activeLightIndex], vd.positionWorld, lightShader);
            vec3 L = lightShader.direction;

            // Calculate the BSDF response for this light source
            BSDF coat_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            mx_dielectric_bsdf_reflection(L, V, P, occlusion, coat, vec3(1.000000, 1.000000, 1.000000), coat_IOR, coat_roughness_vector_out, coat_normal, coat_tangent_out, 0, 0, coat_bsdf_out);
            BSDF metal_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            mx_conductor_bsdf_reflection(L, V, P, occlusion, 1.000000, artistic_ior_ior, artistic_ior_extinction, main_roughness_out, normal, main_tangent_out, 0, metal_bsdf_out);
            BSDF specular_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            specular_bsdf_out.ior = thin_film_IOR;
            specular_bsdf_out.thickness = thin_film_thickness;
            mx_dielectric_bsdf_reflection(L, V, P, occlusion, specular, specular_color, specular_IOR, main_roughness_out, normal, main_tangent_out, 0, 0, specular_bsdf_out);
            BSDF transmission_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            BSDF sheen_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            mx_sheen_bsdf_reflection(L, V, P, occlusion, sheen, sheen_color, sheen_roughness, normal, sheen_bsdf_out);
            BSDF translucent_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            mx_translucent_bsdf_reflection(L, V, P, occlusion, 1.000000, coat_affected_subsurface_color_out, normal, translucent_bsdf_out);
            BSDF subsurface_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            mx_subsurface_bsdf_reflection(L, V, P, occlusion, 1.000000, coat_affected_subsurface_color_out, subsurface_radius_scaled_out, subsurface_anisotropy, normal, subsurface_bsdf_out);
            BSDF selected_subsurface_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            selected_subsurface_bsdf_out.response = mix(subsurface_bsdf_out.response, translucent_bsdf_out.response, subsurface_selector_out);
            selected_subsurface_bsdf_out.throughput = mix(subsurface_bsdf_out.throughput, translucent_bsdf_out.throughput, subsurface_selector_out);
            BSDF diffuse_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            mx_oren_nayar_diffuse_bsdf_reflection(L, V, P, occlusion, base, coat_affected_diffuse_color_out, diffuse_roughness, normal, diffuse_bsdf_out);
            BSDF subsurface_mix_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            subsurface_mix_out.response = mix(diffuse_bsdf_out.response, selected_subsurface_bsdf_out.response, subsurface);
            subsurface_mix_out.throughput = mix(diffuse_bsdf_out.throughput, selected_subsurface_bsdf_out.throughput, subsurface);
            BSDF sheen_layer_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            sheen_layer_out.response = sheen_bsdf_out.response + subsurface_mix_out.response * sheen_bsdf_out.throughput;
            sheen_layer_out.throughput = sheen_bsdf_out.throughput * subsurface_mix_out.throughput;
            BSDF transmission_mix_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            transmission_mix_out.response = mix(sheen_layer_out.response, transmission_bsdf_out.response, transmission);
            transmission_mix_out.throughput = mix(sheen_layer_out.throughput, transmission_bsdf_out.throughput, transmission);
            BSDF specular_layer_with_thin_film_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            specular_layer_with_thin_film_out.response = specular_bsdf_out.response + transmission_mix_out.response * specular_bsdf_out.throughput;
            specular_layer_with_thin_film_out.throughput = specular_bsdf_out.throughput * transmission_mix_out.throughput;
            BSDF metalness_mix_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            metalness_mix_out.response = mix(specular_layer_with_thin_film_out.response, metal_bsdf_out.response, metalness);
            metalness_mix_out.throughput = mix(specular_layer_with_thin_film_out.throughput, metal_bsdf_out.throughput, metalness);
            vec3 metalness_mix_attenuated_out_in2_clamped = clamp(coat_attenuation_out, 0.0, 1.0);
            BSDF metalness_mix_attenuated_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            metalness_mix_attenuated_out.response = metalness_mix_out.response * metalness_mix_attenuated_out_in2_clamped;
            metalness_mix_attenuated_out.throughput = metalness_mix_out.throughput * metalness_mix_attenuated_out_in2_clamped;
            BSDF coat_layer_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            coat_layer_out.response = coat_bsdf_out.response + metalness_mix_attenuated_out.response * coat_bsdf_out.throughput;
            coat_layer_out.throughput = coat_bsdf_out.throughput * metalness_mix_attenuated_out.throughput;

            // Accumulate the light's contribution
            shader_constructor_out.color += lightShader.intensity * coat_layer_out.response;
        }

        // Ambient occlusion
        occlusion = 1.0;

        // Add environment contribution
        {
            BSDF coat_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            mx_dielectric_bsdf_indirect(V, coat, vec3(1.000000, 1.000000, 1.000000), coat_IOR, coat_roughness_vector_out, coat_normal, coat_tangent_out, 0, 0, coat_bsdf_out);
            BSDF metal_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            mx_conductor_bsdf_indirect(V, 1.000000, artistic_ior_ior, artistic_ior_extinction, main_roughness_out, normal, main_tangent_out, 0, metal_bsdf_out);
            BSDF specular_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            specular_bsdf_out.ior = thin_film_IOR;
            specular_bsdf_out.thickness = thin_film_thickness;
            mx_dielectric_bsdf_indirect(V, specular, specular_color, specular_IOR, main_roughness_out, normal, main_tangent_out, 0, 0, specular_bsdf_out);
            BSDF transmission_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            BSDF sheen_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            mx_sheen_bsdf_indirect(V, sheen, sheen_color, sheen_roughness, normal, sheen_bsdf_out);
            BSDF translucent_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            mx_translucent_bsdf_indirect(V, 1.000000, coat_affected_subsurface_color_out, normal, translucent_bsdf_out);
            BSDF subsurface_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            mx_subsurface_bsdf_indirect(V, 1.000000, coat_affected_subsurface_color_out, subsurface_radius_scaled_out, subsurface_anisotropy, normal, subsurface_bsdf_out);
            BSDF selected_subsurface_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            selected_subsurface_bsdf_out.response = mix(subsurface_bsdf_out.response, translucent_bsdf_out.response, subsurface_selector_out);
            selected_subsurface_bsdf_out.throughput = mix(subsurface_bsdf_out.throughput, translucent_bsdf_out.throughput, subsurface_selector_out);
            BSDF diffuse_bsdf_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            mx_oren_nayar_diffuse_bsdf_indirect(V, base, coat_affected_diffuse_color_out, diffuse_roughness, normal, diffuse_bsdf_out);
            BSDF subsurface_mix_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            subsurface_mix_out.response = mix(diffuse_bsdf_out.response, selected_subsurface_bsdf_out.response, subsurface);
            subsurface_mix_out.throughput = mix(diffuse_bsdf_out.throughput, selected_subsurface_bsdf_out.throughput, subsurface);
            BSDF sheen_layer_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            sheen_layer_out.response = sheen_bsdf_out.response + subsurface_mix_out.response * sheen_bsdf_out.throughput;
            sheen_layer_out.throughput = sheen_bsdf_out.throughput * subsurface_mix_out.throughput;
            BSDF transmission_mix_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            transmission_mix_out.response = mix(sheen_layer_out.response, transmission_bsdf_out.response, transmission);
            transmission_mix_out.throughput = mix(sheen_layer_out.throughput, transmission_bsdf_out.throughput, transmission);
            BSDF specular_layer_with_thin_film_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            specular_layer_with_thin_film_out.response = specular_bsdf_out.response + transmission_mix_out.response * specular_bsdf_out.throughput;
            specular_layer_with_thin_film_out.throughput = specular_bsdf_out.throughput * transmission_mix_out.throughput;
            BSDF metalness_mix_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            metalness_mix_out.response = mix(specular_layer_with_thin_film_out.response, metal_bsdf_out.response, metalness);
            metalness_mix_out.throughput = mix(specular_layer_with_thin_film_out.throughput, metal_bsdf_out.throughput, metalness);
            vec3 metalness_mix_attenuated_out_in2_clamped = clamp(coat_attenuation_out, 0.0, 1.0);
            BSDF metalness_mix_attenuated_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            metalness_mix_attenuated_out.response = metalness_mix_out.response * metalness_mix_attenuated_out_in2_clamped;
            metalness_mix_attenuated_out.throughput = metalness_mix_out.throughput * metalness_mix_attenuated_out_in2_clamped;
            BSDF coat_layer_out = BSDF(vec3(0.0),vec3(1.0), 0.0, 0.0);
            coat_layer_out.response = coat_bsdf_out.response + metalness_mix_attenuated_out.response * coat_bsdf_out.throughput;
            coat_layer_out.throughput = coat_bsdf_out.throughput * metalness_mix_attenuated_out.throughput;

            shader_constructor_out.color += occlusion * coat_layer_out.response;
        }

        // Add surface emission
        {
            EDF emission_edf_out = EDF(0.0);
            mx_uniform_edf(N, V, emission_weight_attenuated_out, emission_edf_out);
            shader_constructor_out.color += emission_edf_out;
        }

        shader_constructor_out.transparency = vec3(0.0);
    }

    out1 = shader_constructor_out;
}

void main()
{
    vec3 geomprop_Nworld_out = normalize(vd.normalWorld);
    vec3 geomprop_Tworld_out = normalize(vd.tangentWorld);
    surfaceshader SR_gold_out = surfaceshader(vec3(0.0),vec3(0.0));
    NG_standard_surface_surfaceshader_100(base, base_color, diffuse_roughness, metalness, specular, specular_color, specular_roughness, specular_IOR, specular_anisotropy, specular_rotation, transmission, transmission_color, transmission_depth, transmission_scatter, transmission_scatter_anisotropy, transmission_dispersion, transmission_extra_roughness, subsurface, subsurface_color, subsurface_radius, subsurface_scale, subsurface_anisotropy, sheen, sheen_color, sheen_roughness, coat, coat_color, coat_roughness, coat_anisotropy, coat_rotation, coat_IOR, geomprop_Nworld_out, coat_affect_color, coat_affect_roughness, thin_film_thickness, thin_film_IOR, emission, emission_color, opacity, thin_walled, geomprop_Nworld_out, geomprop_Tworld_out, SR_gold_out);
    out1 = vec4(SR_gold_out.color, 1.0);
}

