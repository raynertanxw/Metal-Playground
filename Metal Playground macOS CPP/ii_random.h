#ifndef II_RANDOM_H
#define II_RANDOM_H

#include <cassert>

typedef int32_t B32;
typedef int32_t I32;
typedef uint32_t U32;
typedef float F32;
typedef double F64;

#define U32_MAX UINT32_MAX
static inline F32 F32Lerp(F32 a, F32 t, F32 b) {
    return a + (b-a)*t;
}
static inline F64 F64Lerp(F64 a, F64 t, F64 b) {
    return a + (b-a)*t;
}

typedef struct { U32 seed; } RNG;

U32 RandomU32(RNG *r) { // wang hash
  r->seed  = (r->seed ^ 61) ^ (r->seed >> 16);
  r->seed *= 9;
  r->seed  = r->seed ^ (r->seed >> 4);
  r->seed *= 0x27d4eb2d;
  r->seed  = r->seed ^ (r->seed >> 15);
  return r->seed;
}

static F32 RandomF01     (RNG *rng                     ) {                     return RandomU32(rng)/(F32)U32_MAX;            }
static F32 RandomN11     (RNG *rng                     ) {                     return RandomF01(rng)*2 - 1;                   }
static U32 RandomChoice  (RNG *rng, U32 choiceCount    ) {                     return RandomU32(rng)%choiceCount;             }
static B32 RandomChance  (RNG *rng, F32 chanceOfSuccess) {                     return RandomF01(rng) < chanceOfSuccess;       }
static I32 RandomRangeI32(RNG *rng, I32 min, I32 max   ) { assert(max >= min); return min + RandomChoice(rng, max - min + 1); }
static F32 RandomRangeF32(RNG *rng, F32 min, F32 max   ) { assert(max >= min); return F32Lerp(min, RandomF01(rng), max);      }
static F64 RandomRangeF64(RNG *rng, F64 min, F64 max   ) { assert(max >= min); return F64Lerp(min, RandomF01(rng), max);      }
#define    RandomEnum(         rng, type, first, last  ) (                            (type)RandomRangeI32(rng, first, last)  )

#endif
