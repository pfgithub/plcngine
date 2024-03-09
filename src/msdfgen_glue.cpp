#define MSDFGEN_IMPL_CPP

#include "msdfgen_glue.h"

extern "C" {

struct cz_Bitmap3f {
    Bitmap<float, 3> instance;
};

struct cz_Shape {
    Shape instance;
};

FreetypeHandle* cz_initializeFreetype() {
    return initializeFreetype();
}

void cz_deinitializeFreetype(FreetypeHandle* ft) {
    return deinitializeFreetype(ft);
}

FontHandle* cz_loadFontData(FreetypeHandle* ft, const uint8_t* data, int length) {
    return loadFontData(ft, data, length);
}

void cz_destroyFont(FontHandle* ft) {
    return destroyFont(ft);
}

bool cz_loadGlyph(cz_Shape* output, FontHandle* font, uint32_t unicode, double* advance) {
    return loadGlyph(output->instance, font, unicode, advance);
}

cz_Bitmap3f* cz_createBitmap3f(int width, int height) {
    cz_Bitmap3f* result = new cz_Bitmap3f();
    result->instance = Bitmap<float, 3>(width, height);
    return result;
}

void cz_destroyBitmap3f(cz_Bitmap3f* bitmap) {
    delete bitmap;
}

float* cz_bitmap3fPixels(cz_Bitmap3f* bitmap) {
    return bitmap->instance;
}

int cz_bitmap3fWidth(cz_Bitmap3f* bitmap) {
    return bitmap->instance.width();
}

int cz_bitmap3fHeight(cz_Bitmap3f* bitmap) {
    return bitmap->instance.height();
}

cz_Shape* cz_createShape() {
    return new cz_Shape();
}

void cz_destroyShape(cz_Shape* shape) {
    delete shape;
}

void cz_shapeNormalize(cz_Shape* shape) {
    shape->instance.normalize();
}
void cz_edgeColoringSimple(cz_Shape* shape, float max_angle) {
    edgeColoringSimple(shape->instance, max_angle);
}

void cz_generateMSDF(cz_Bitmap3f* bitmap, const cz_Shape* shape, double scale_x, double scale_y, double translate_x, double translate_y, double range) {
    generateMSDF(bitmap->instance, shape->instance, Projection(Vector2(scale_x, scale_y), Vector2(translate_x, translate_y)), range);
    // simulate8bit(bitmap->instance);
}

} // extern "C"
