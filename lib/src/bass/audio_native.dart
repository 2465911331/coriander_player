import 'dart:ffi';

final class BassChannelInfo extends Struct {
  @Uint32()
  external int frequency;
  @Uint32()
  external int channels;
  @Uint32()
  external int flags;
  @Uint32()
  external int type;
  @Uint32()
  external int resolution;
  @Uint32()
  external int plugin;
  @Uint32()
  external int sample;
  external Pointer<Char> filename;
}

class BassExtras {
  BassExtras(DynamicLibrary library) {
    setDevice =
        library.lookupFunction<Int32 Function(Uint32), int Function(int)>(
            'BASS_SetDevice');
    data = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
    info = library.lookupFunction<
        Int32 Function(Uint32, Pointer<BassChannelInfo>),
        int Function(int, Pointer<BassChannelInfo>)>('BASS_ChannelGetInfo');
    flags = library.lookupFunction<Uint32 Function(Uint32, Uint32, Uint32),
        int Function(int, int, int)>('BASS_ChannelFlags');
  }
  late final int Function(int, Pointer<Void>, int) data;
  late final int Function(int, Pointer<BassChannelInfo>) info;
  late final int Function(int, int, int) flags;
  late final int Function(int) setDevice;
}

class BassMix {
  BassMix(DynamicLibrary library) {
    create = library.lookupFunction<Uint32 Function(Uint32, Uint32, Uint32),
        int Function(int, int, int)>('BASS_Mixer_StreamCreate');
    add = library.lookupFunction<Int32 Function(Uint32, Uint32, Uint32),
        int Function(int, int, int)>('BASS_Mixer_StreamAddChannel');
    remove = library.lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'BASS_Mixer_ChannelRemove');
  }
  late final int Function(int, int, int) create;
  late final int Function(int, int, int) add;
  late final int Function(int) remove;
}
