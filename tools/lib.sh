# Shared helpers. Sourced by both tools/build and bin/godot.
# Lives in one place so the platform -> binary-name mapping can never drift
# between the thing that BUILDS the binary and the thing that RUNS it.
#
# Not executable on its own. `source` it.

# Resolve the directory this file lives in, even when sourced.
_voxmvp_lib_dir() {
	# BASH_SOURCE[0] is this file regardless of who sourced it.
	cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

# Project root is one level up from tools/.
VOXMVP_ROOT="$(cd "$(_voxmvp_lib_dir)/.." && pwd)"

# Print the expected Godot editor binary name for the current platform.
# Both halves of the toolchain agree on this single function.
#
# The .double here must stay in lockstep with precision=double in
# versions.env's SCONS_EXTRA_ARGS. If you ever drop double precision,
# both have to change together.
platform_binary_name() {
	local kernel arch
	kernel="$(uname -s)"
	arch="$(uname -m)"

	case "$kernel" in
		Linux)
			# x86_64 desktop build.
			echo "godot.linuxbsd.editor.double.${arch}"
			;;
		Darwin)
			# Apple Silicon laptop. Godot reports arm64 as "arm64".
			# NOTE: confirm this exact string against the actual file
			# produced by the laptop build before trusting it — Godot's
			# macOS naming has historically had vari/SCons-arch quirks.
			echo "godot.macos.editor.double.${arch}"
			;;
		*)
			echo "platform_binary_name: unsupported kernel '$kernel'" >&2
			return 1
			;;
	esac
}

# Absolute path to where the built binary should land.
platform_binary_path() {
	local name
	name="$(platform_binary_name)" || return 1
	echo "${VOXMVP_ROOT}/${GODOT_DIR_REL}/bin/${name}"
}

# A SCons-friendly platform token, in case the build script wants it.
scons_platform() {
	case "$(uname -s)" in
		Linux)  echo "linuxbsd" ;;
		Darwin) echo "macos"    ;;
		*) return 1 ;;
	esac
}

# --- godot_voxel module wiring ---------------------------------------------
# godot_voxel is NOT name-agnostic. Its docs say, emphatically, that the
# module folder MUST be named `voxel` — `godot/modules/voxel`. The module's
# own code and registration hardcode that name. custom_modules= does NOT
# work, because it derives the module name from the directory name, which
# is `godot_voxel`, producing initialize_godot_voxel_module() while the
# module's code produces initialize_voxel_module(). They must match.
#
# So: a symlink named `voxel` inside godot/modules/, pointing at the
# godot_voxel checkout. These two helpers give the build script one place
# to resolve both ends of that symlink.

# Absolute path to the godot_voxel repo checkout.
godot_voxel_dir() {
	echo "$(cd "${VOXMVP_ROOT}/${GODOT_VOXEL_DIR_REL}" && pwd)"
}

# Absolute path to where the symlink must live (and must be named `voxel`).
voxel_module_link() {
	echo "${VOXMVP_ROOT}/${GODOT_DIR_REL}/modules/voxel"
}
