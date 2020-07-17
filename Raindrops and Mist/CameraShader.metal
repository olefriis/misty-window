#include <metal_stdlib>
using namespace metal;

typedef struct {
    float4 renderedCoordinate [[position]];
    float2 textureCoordinate;
} TextureMappingVertex;

vertex TextureMappingVertex mapTexture(unsigned int vertex_id [[ vertex_id ]]) {
    float4x4 renderedCoordinates = float4x4(float4( -1.0, -1.0, 0.0, 1.0 ),      /// (x, y, depth, W)
                                            float4(  1.0, -1.0, 0.0, 1.0 ),
                                            float4( -1.0,  1.0, 0.0, 1.0 ),
                                            float4(  1.0,  1.0, 0.0, 1.0 ));

    float4x2 textureCoordinates = float4x2(float2( 0.0, 1.0 ), /// (x, y)
                                           float2( 1.0, 1.0 ),
                                           float2( 0.0, 0.0 ),
                                           float2( 1.0, 0.0 ));
    TextureMappingVertex outVertex;
    outVertex.renderedCoordinate = renderedCoordinates[vertex_id];
    outVertex.textureCoordinate = textureCoordinates[vertex_id];
    
    return outVertex;
}

fragment float4 displayTexture(TextureMappingVertex mappingVertex [[ stage_in ]],
                               texture2d<float, access::sample> camera [[ texture(0) ]],
                               texture2d<float, access::sample> blur [[ texture(1) ]],
                               texture2d<float, access::sample> mist [[ texture(2) ]],
                               constant float &raindropsCount [[ buffer(0) ]],
                               constant float2 *raindrops [[ buffer(1) ]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 offset = mappingVertex.textureCoordinate;
    float2 normalizedOffset = float2(offset.x, offset.y * camera.get_height()/ camera.get_width());

    float dropRadius = 0.01;
    for (int raindrop = 0; raindrop < raindropsCount; raindrop++) {
        float2 raindropPos = raindrops[raindrop];
        float dist = distance(normalizedOffset, raindropPos);
        if (dist < dropRadius) {
            float2 raindropToHere = normalizedOffset - raindropPos;
            float reflection = tan(dist/dropRadius * 0.9) * 3;
            return camera.sample(s, offset - reflection*raindropToHere);
        }
    }

    float mistRatio = mist.sample(s, offset).r;
    return mix(camera.sample(s, offset), blur.sample(s, offset), mistRatio);
}

kernel void addMist(texture2d<float, access::read_write> texture [[ texture(0) ]],
                    constant float &raindropsCount [[ buffer(0) ]],
                    constant float2 *raindrops [[ buffer(1) ]],
                    uint2 gid [[thread_position_in_grid]]) {
    float2 normalizedOffset = float2((float) gid.x / texture.get_width(), (float) gid.y / texture.get_width());
    float dropRadius = 0.01;
    for (int raindrop = 0; raindrop < raindropsCount; raindrop++) {
        float2 raindropPos = raindrops[raindrop];
        float dist = distance(normalizedOffset, raindropPos);
        if (dist < dropRadius) {
            texture.write(0, gid);
        }
    }


    uint2 textureIndex(gid.x, gid.y);
    float previousWeight = texture.read(textureIndex).r;
    float newWeight = min(1.0, previousWeight + 0.01);
    texture.write(float4(newWeight), gid);
}
