class FuseExt2 < Formula
  desc "Mount ext2/ext3/ext4 filesystems read-only on modern macOS via macFUSE"
  homepage "https://github.com/moonsoup/fuse-ext2"
  url "https://github.com/moonsoup/fuse-ext2/archive/refs/tags/v0.0.11.2.tar.gz"
  sha256 "9edd4b3d34e23dafa25e20d1231c40c6b019ac2794c9f7533a8c68e72f78a9bc"
  license "GPL-2.0-only"

  # macFUSE lives in /usr/local, which Homebrew's supercompiler strips. Use the
  # standard environment so those include/lib paths survive to the real compiler.
  env :std

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "libtool" => :build
  depends_on "m4" => :build
  depends_on "pkgconf" => :build
  depends_on "e2fsprogs"

  # macFUSE provides the FUSE headers/framework this links against. It's a cask
  # (a kernel extension), so it can't be an ordinary formula dependency; the
  # install step checks for it and fails with a clear message if it's absent.
  def install
    unless File.exist?("/usr/local/include/fuse/fuse.h")
      odie <<~EOS
        macFUSE is required and was not found.
        Install it first, then re-run this install:
          brew install --cask macfuse
      EOS
    end

    # macFUSE lives in /usr/local, which Homebrew's build sandbox normally
    # strips. The /usr/local/include/fuse *subdirectory* survives, so put the
    # FUSE include there (in CFLAGS) and link libfuse explicitly. The macFUSE
    # libfuse.dylib references MFMount.framework, hence the -F search path.
    # e2fsprogs headers/libs are supplied automatically by its dependency.
    macfuse_fw = "/Library/Filesystems/macfuse.fs/Contents/Frameworks"
    ENV["LIBTOOLIZE"] = "glibtoolize"
    ENV.append "CFLAGS", "-I/usr/local/include/fuse"
    ENV.append "LDFLAGS", "-L/usr/local/lib"
    ENV.append "LDFLAGS", "-F#{macfuse_fw}" if File.directory?(macfuse_fw)
    ENV.append "LIBS", "-lfuse"

    system "./autogen.sh"
    system "./configure", "--disable-dependency-tracking", "--prefix=#{prefix}"
    # Build only the main driver binary. The optional macOS auto-mount helpers
    # (tools/) don't build against the current SDK and aren't needed for manual
    # `fuse-ext2 <device> <mountpoint>` use.
    system "make", "-C", "fuse-ext2", "fuse-ext2"
    bin.install "fuse-ext2/fuse-ext2"
    bin.install "contrib/fuse-ext2-mount" if File.exist?("contrib/fuse-ext2-mount")
    man1.install "fuse-ext2/fuse-ext2.1" if File.exist?("fuse-ext2/fuse-ext2.1")
  end

  def caveats
    <<~EOS
      fuse-ext2 needs macFUSE (a kernel extension). If you don't have it yet:
        brew install --cask macfuse
      Then enable it (a kext, so this is required, not optional):
        1. System Settings -> Privacy & Security -> Allow the blocked macFUSE extension
        2. RESTART your Mac (it only loads after a reboot)
      On Apple Silicon, first-time kext loading also needs Reduced Security:
      boot into Recovery -> Startup Security Utility -> Reduced Security +
      "Allow user management of kernel extensions", then restart. See
      https://macfuse.github.io/

      Mount an ext2/3/4 device or image read-only:
        fuse-ext2 /dev/diskNsM /path/to/mountpoint -o ro,allow_other
      Reading data owned by a uid that doesn't exist on this Mac (common with
      drives recovered from another machine):
        fuse-ext2 /dev/diskNsM /path/to/mountpoint -o ro,allow_other,no_default_permissions
      Unmount:
        umount /path/to/mountpoint
    EOS
  end

  test do
    # `-h` prints the usage/banner and exits 9; assert the banner is present.
    assert_match "EXT2FS", shell_output("#{bin}/fuse-ext2 -h 2>&1", 9)
  end
end
