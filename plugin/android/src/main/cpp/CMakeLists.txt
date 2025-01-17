
# For more information about using CMake with Android Studio, read the
# documentation: https://d.android.com/studio/projects/add-native-code.html

# Sets the minimum version of CMake required to build the native library.

cmake_minimum_required(VERSION 3.18.1)

# Declares and names the project.

project("plugin")

# Creates and names a library, sets it as either STATIC
# or SHARED, and provides the relative paths to its source code.
# You can define multiple libraries, and CMake builds them for you.
# Gradle automatically packages shared libraries with your APK.

# configure import libs
set(dependency_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../dependency)

add_library( tensorflowlite SHARED IMPORTED )
set_target_properties( tensorflowlite PROPERTIES IMPORTED_LOCATION
    ${dependency_DIR}/tensorflowlite/jni/${ANDROID_ABI}/libtensorflowlite_jni.so )

add_library( tensorflowlite_gpu SHARED IMPORTED )
set_target_properties( tensorflowlite_gpu PROPERTIES IMPORTED_LOCATION
    ${dependency_DIR}/tensorflowlite/jni/${ANDROID_ABI}/libtensorflowlite_gpu_jni.so )

add_library( renderscript-intrinsics-replacement-toolkit SHARED IMPORTED )
set_target_properties( renderscript-intrinsics-replacement-toolkit PROPERTIES IMPORTED_LOCATION
    ${dependency_DIR}/renderscript-intrinsics-replacement-toolkit/jni/${ANDROID_ABI}/librenderscript-toolkit.so )

add_library( # Sets the name of the library.
             plugin

             # Sets the library as a shared library.
             SHARED

             # Provides a relative path to your source file(s).
             filter/brightness.cpp
             filter/color_levels.cpp
             filter/contrast.cpp
             filter/crop.cpp
             filter/curve.cpp
             filter/hslhsv.cpp
             filter/orientation.cpp
             filter/saturation.cpp
             filter/tint.cpp
             filter/warmth.cpp
             filter/yuv.cpp
             lib/spline/spline.cpp
             arbitrary_style_transfer.cpp
             deep_lap_3.cpp
             esrgan.cpp
             exception.cpp
             image_splitter.cpp
             neur_op.cpp
             stopwatch.cpp
             tflite_wrapper.cpp
             util.cpp
             zero_dce.cpp
             )
set_target_properties( plugin PROPERTIES COMPILE_OPTIONS -fopenmp )

# Searches for a specified prebuilt library and stores the path as a
# variable. Because CMake includes system libraries in the search path by
# default, you only need to specify the name of the public NDK library
# you want to add. CMake verifies that the library exists before
# completing its build.

find_library( # Sets the name of the path variable.
              log-lib

              # Specifies the name of the NDK library that
              # you want CMake to locate.
              log )

find_library( android-lib android )

target_include_directories( plugin PRIVATE
                            ${dependency_DIR}/tensorflowlite/headers
                            ${dependency_DIR}/renderscript-intrinsics-replacement-toolkit/headers )

# Specifies libraries CMake should link to your target library. You
# can link multiple libraries, such as libraries you define in this
# build script, prebuilt third-party libraries, or system libraries.

target_link_libraries( # Specifies the target library.
                       plugin

                       # Links the target library to the log library
                       # included in the NDK.
                       ${log-lib}
                       ${android-lib}
                       tensorflowlite
                       tensorflowlite_gpu
                       renderscript-intrinsics-replacement-toolkit
                       -fopenmp -static-openmp )
