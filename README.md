# IQmol3
IQmol version 3

This is IQmol, a molecular builder and visualization package written by Andrew
Gilbert.  IQmol is able to build molecules, set up and submit input for Q-Chem
calculations, and analyse the output.  Analyses include display of molecular
surfaces (densites, molecular orbitals) and animations of frequencies and 
reaction pathways.  A user guide can be found in the doc directory.

For an up-to-date list of features and pre-compiled binaries, please visit the 
website:  http://iqmol.org

This is a rebase of the original code that migrates to CMake and updates several
of the external libraries, including them as submodules in an attempt to ease the
build process.

The source relies on submodules, so to checkout the code use the recursive flag:

```
git clone --recursive https://github.com/nutjunkie/IQmol3.git
```

To compile, make sure that you QT installation can be found by cmake.  This
means that the CMAKE\_PREFIX\_PATH environment variable should include the
directory containing the Qt5Config.cmake file
```
export CMAKE_PREFIX_PATH=/directory/containing_Qt5Config.cmake
./configure
cd build
make
```

On macOS 26 on an Intel Mac, use Homebrew's `qt@5` and build explicitly for
`x86_64`.  The `configure` script now auto-detects a Homebrew Qt 5 install from
`/usr/local` on Intel Macs, but the fully explicit path is:

```
brew install qt@5 openssl@3 zstd boost gcc
export IQMOL_QT_ROOT="$(brew --prefix qt@5)"
export CMAKE_PREFIX_PATH="$IQMOL_QT_ROOT/lib/cmake"
export MACOSX_DEPLOYMENT_TARGET=26.0
./configure
cd build
make
```

For a direct CMake invocation on Intel macOS 26:

```
QT_PREFIX="$(brew --prefix qt@5)"
OPENSSL_PREFIX="$(brew --prefix openssl@3)"
ZSTD_PREFIX="$(brew --prefix zstd)"
BOOST_PREFIX="$(brew --prefix boost)"
FC="$(find "$(brew --prefix gcc)/bin" -name 'gfortran-*' | head -n 1)"

cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DCMAKE_PREFIX_PATH="$QT_PREFIX/lib/cmake;$OPENSSL_PREFIX;$ZSTD_PREFIX;$BOOST_PREFIX" \
  -DOPENSSL_ROOT_DIR="$OPENSSL_PREFIX" \
  -DZSTD_ROOT="$ZSTD_PREFIX" \
  -DBoost_ROOT="$BOOST_PREFIX" \
  -DCMAKE_Fortran_COMPILER="$FC"

cmake --build build
```
