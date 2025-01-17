// __multiversion__
#include "fragmentVersionSimple.h"
#include "uniformPerFrameConstants.h"

LAYOUT_BINDING(0) uniform sampler2D TEXTURE_0;

precision highp float;
#include "common.glsl"
varying vec3 cpos;

#ifdef ENABLE_VOLUMETRIC_CLOUD
float noise3d(vec3 pos){
	vec3 fp = csmooth(fract(pos));
	vec3 ip = floor(pos);
	return mix(texture2D(TEXTURE_0, ((ip.xy + ip.z * vec2(17, 37)) + fp.xy + 0.5) * 0.00390625).r, texture2D(TEXTURE_0, ((ip.xy + (ip.z + 1.0) * vec2(17, 37)) + fp.xy + 0.5) * 0.00390625).r, fp.z);
}
float sint(float yalt, float h){
	float r = 6371e3 + h, ds = yalt * 6371e3;
	return -ds + sqrt((ds * ds) + (r * r) - 4.058964e13);
}

const float cminh = VOLUMETRIC_CLOUD_HEIGHT;
const float cmaxh = VOLUMETRIC_CLOUD_HEIGHT + VOLUMETRIC_CLOUD_THICKNESS;
// https://github.com/robobo1221/robobo1221Shaders
float ccd(vec3 pos){
	if(pos.y < cminh || pos.y > cmaxh) return 0.0;
	float tot = 0.0, den = saturate(1.0 - wrain);
	vec3 movp = pos * 0.001;
	for(int i = 0; i < 5; i++){
		tot += noise3d(movp) * den;
		den *= 0.5;
		movp *= 2.5;
		movp.xz += TOTAL_REAL_WORLD_TIME * 0.05;
	}
	float hf = (pos.y - cminh) / VOLUMETRIC_CLOUD_THICKNESS;
	float ha = saturate(map(hf, 0.0, 0.4, 0.0, 1.0) * map(hf, 0.7, 1.0, 1.0, 0.0));
	float cov = (texture2D(TEXTURE_0, pos.xz * 2e-5 + TOTAL_REAL_WORLD_TIME * 1e-4).b * 3.0 - 1.7) * 0.5 + VOLUMETRIC_CLOUD_DENSITY;
	return saturate(tot * ha * cov - (ha * 0.5 + hf * 0.5)) * VOLUMETRIC_CLOUD_SHARPNESS;
}

float ccl(vec3 startp, vec3 lpos){
	float codl = 0.0;
	float ss = VOLUMETRIC_CLOUD_THICKNESS / float(VOLUMETRIC_CLOUD_LIGHT_STEPS);
	for(int i = 0; i < VOLUMETRIC_CLOUD_LIGHT_STEPS; i++, startp += lpos * ss) codl += ccd(startp) * ss;
	return exp(-codl * 0.1);
}

vec3 ccs(vec3 startp, vec3 lpos, vec3 lcol, vec3 scol, float cdens, float cost){
	float cis = exp(-clamp(VOLUMETRIC_CLOUD_THICKNESS * 0.7 - startp.y, 0.0, cminh) * 0.005) * 0.6 + 0.3;
	float powd = 1.0 - exp(-cdens * 2.0), cls = ccl(startp, lpos), ph = cphase(cost);
	return  (lcol * cls * powd * ph * 4.0) + (scol * cis);
}

vec4 ccv(vec3 vwpos, vec3 lpos, vec3 sunc, vec3 monc, vec3 skyzc, float dither){
	vec3 startp = vwpos * sint(vwpos.y, cminh), endp = vwpos * sint(vwpos.y, cmaxh);
	vec3 dir = (endp - startp) / float(VOLUMETRIC_CLOUD_STEPS);
		startp = startp + dir * dither;
	float cost = dot(vwpos, lpos), tr = 1.0, codl = 0.0;
	vec3 tclsc = vec3(0.0);
	for(int i = 0; i < VOLUMETRIC_CLOUD_STEPS; i++, startp += dir){
		float cdens = ccd(startp) * length(dir);
		if(cdens <= 0.0) continue;
		float cod = exp(-cdens);
		vec3 cs = ccs(startp, lpos, (sunc + monc * hpi), skyzc, cdens, cost);
		tclsc += cs * (-tr * cod + tr);
		tr *= cod;
    }
	return mix(vec4(tclsc * hpi, tr), vec4(0.0, 0.0, 0.0, 1.0), saturate(length(startp) * 2.5e-5));
}
#endif

#ifdef ENABLE_CIRRUS_CLOUD
vec4 ccc(vec3 vwpos, vec3 lpos, vec3 sunc, vec3 monc){
	float tot = 0.0, den = saturate(1.0 - wrain);
	vec2 movp = vwpos.xz / vwpos.y;
		movp *= 1.5;
		movp *= rotate2d(0.5);
		movp.x += TOTAL_REAL_WORLD_TIME * 0.001;
	for(int i = 0; i < 4; i++){
		tot += texture2D(TEXTURE_0, movp * 0.00390625).r * den;
		den *= 0.55;
		movp *= 2.5;
		movp.y += movp.y * (0.7 + tot * 0.3);
		movp.x += TOTAL_REAL_WORLD_TIME * 0.01;
	}
		tot = 1.0 - pow(0.8, max0(1.0 - tot));
	float phase = cphase2(dot(vwpos, lpos));
	float cpowd = 1.0 - exp(-tot * 2.0);
	return mix(vec4((sunc * pi + monc) * cpowd * phase, exp(-tot)), vec4(0.0,0.0,0.0,1.0), smoothstep(0.5, 0.0, vwpos.y));
}
#endif

void main(){
	vec3 ajpos = normalize(vec3(cpos.x, -cpos.y + 0.128, -cpos.z));
	vec3 spos = vec3(0.0), tlpos = vec3(0.0), sunc = vec3(0.0), monc = vec3(0.0), skyzc = vec3(0.0);
	clpos(tlpos, spos);
	atml(spos, sunc, monc, skyzc);
	vec4 color = vec4(0.0, 0.0, 0.0, 1.0);
		color.rgb = csky(ajpos, spos);
	#ifdef ENABLE_CIRRUS_CLOUD
		vec4 pcloud = ccc(ajpos, tlpos, sunc, monc);
		color.rgb = color.rgb * pcloud.a + pcloud.rgb;
	#endif
	#ifdef ENABLE_VOLUMETRIC_CLOUD
		float dbnoise = texture2D(TEXTURE_0, gl_FragCoord.xy / 256.0).r;
		vec4 vcloud = ccv(ajpos, tlpos, sunc, monc, skyzc, dbnoise);
		color.rgb = color.rgb * vcloud.a + vcloud.rgb;
	#endif
		color.rgb = colcor(color.rgb);
	gl_FragColor = color;
}
