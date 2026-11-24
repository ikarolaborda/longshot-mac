The Mac builder includes the Apple silicon RenHDrum library from the [Longshot v3.2.0 source](https://git.magicbean.dev/MagicBeanDev/Longshot/src/tag/v3.2.0/third_party/renhdrum). The upstream source revision is 79d192c655b52ef69a42918e385ff79b6dfabd1f. The licenses are in ../../licenses/renhdrum.

To rebuild it on Apple silicon, run these commands from a checkout of that upstream revision.

```sh
mkdir -p third_party/renhdrum/vendor
ln -s ../../opus third_party/renhdrum/vendor/opus
cargo build --manifest-path third_party/renhdrum/Cargo.toml --release --locked
cp third_party/renhdrum/target/release/librenhdrum.dylib renhdrum.dylib
install_name_tool -id @rpath/renhdrum.dylib renhdrum.dylib
codesign --force --sign - renhdrum.dylib
```
