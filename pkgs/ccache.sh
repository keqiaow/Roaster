# ================================================================
# Compile Snappy
# ================================================================

[ -e $STAGE/ccache ] && ( set -xe
    cd $SCRATCH
    
    # ------------------------------------------------------------

    until git clone --depth 1 --single-branch -b "$(git ls-remote --tags "$GIT_MIRROR/ccache/ccache.git" | sed -n 's/.*[[:space:]]refs\/tags\/\(v[0-9\.]*\)[[:space:]]*$/\1/p' | sort -V | tail -n1)" "$GIT_MIRROR/ccache/ccache.git"; do echo 'Retrying'; done
    cd ccache

    # ------------------------------------------------------------

    . "$ROOT_DIR/pkgs/utils/fpm/pre_build.sh"

    (
        set +xe
        . scl_source enable devtoolset-7
        set -xe

        time ./autogen.sh
        time ./configure --prefix="$INSTALL_ABS"
        time make -j$(nproc)
        time make install -j
    )

    "$ROOT_DIR/pkgs/utils/fpm/install_from_git.sh"

    # ------------------------------------------------------------

    cd
    rm -rf $SCRATCH/ccache
)
sudo rm -vf $STAGE/ccache
sync || true
