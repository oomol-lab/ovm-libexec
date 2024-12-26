#! /usr/bin/env bash

set -e

_get_krunkit() {
	cd "$workspace" 
	mkdir -p "$workspace/krunkit_temp" 
	cd "$workspace/krunkit_temp"
	gh release download v0.1.4 -R containers/krunkit --pattern "krunkit-*" --clobber
	tar -zxvf krunkit-*.tgz -C ./
	mv bin/* lib/* "$workspace/out"
	cd "$workspace"
}

_build_vfkit() {
	cd "$workspace"
	v_tag="v0.6.0"
	rm -rf ./vfkit_temp
	git clone https://github.com/crc-org/vfkit vfkit_temp
	cd ./vfkit_temp
	git checkout $v_tag
	make out/vfkit-amd64
	mv ./out/vfkit-amd64 "$workspace/out/vfkit"
	cd "$workspace"
}

_build_gvproxy() {
	cd "$workspace"
	rm -rf gvisor-tap-vsock_temp
	git clone https://github.com/containers/gvisor-tap-vsock.git ./gvisor-tap-vsock_temp
	cd ./gvisor-tap-vsock_temp
	git checkout v0.8.1
	make gvproxy
	mv ./bin/gvproxy "$workspace/out/gvproxy"
	cd "$workspace"
}

_pack_output() {
	cd "$workspace/out"
	tar --no-mac-metadata -zcvf "$workspace/libexec-$GOOS-$GOARCH.tar.gz" .
	cd "$workspace"
}

_do_codesign() {
	if [[ -z "$CODESIGN_IDENTITY" ]]; then
		CODESIGN_IDENTITY="-"
	fi

	test -f "$workspace/out/gvproxy" && {
		echo "Signing gvproxy..."
		codesign --force --sign "$CODESIGN_IDENTITY" --options=runtime --timestamp "$workspace/out/gvproxy"
	}

	test -f "$workspace/out/vfkit" && {
		echo "Signing vfkit..."
		codesign --force --sign "$CODESIGN_IDENTITY" --options=runtime --timestamp --entitlements "$workspace/vf.entitlements" "$workspace/out/vfkit"
	}

	test -f "$workspace/out/krunkit" && {
		echo "Signing krunkit..."
		codesign --force --sign "$CODESIGN_IDENTITY" --options=runtime --timestamp --entitlements "$workspace/krunkit.entitlements" "$workspace/out/krunkit"
	}

	find "$workspace/out" -name "*.dylib" -type f -exec sh -c "echo 'Set {} permission to 755'; chmod 755 {}" ';'
	find "$workspace/out" -name "*.dylib" -type f -exec sh -c "echo 'Signing {}...'; codesign --force --sign $CODESIGN_IDENTITY --options=runtime --timestamp {}" ';'
}

build_darwin_arm64() {
	export GOOS=darwin
	export GOARCH=arm64

	echo "Build gvproxy"
	_build_gvproxy

	echo "Download krunkit"
	_get_krunkit

	echo "Do codesign"
	_do_codesign

	echo "Packup output"
	_pack_output
}

build_darwin_amd64() {
	export GOOS=darwin
	export GOARCH=amd64

	echo "Build gvproxy"
	_build_gvproxy

	echo "Build vfkit"
	_build_vfkit

	echo "Do codesign"
	_do_codesign

	echo "Packup output"
	_pack_output
}

main() {
	target_arch=$1
	workspace="$(pwd)"
	if [[ -z $target_arch ]]; then
		echo "Error: missing target"
		exit 2
	fi

	# Clean out dir first
	rm -rf "$workspace/out"
	mkdir -p "$workspace/out"

	if [[ $target_arch == arm64 ]]; then
		echo "Building binaries for darwin arm64"
		build_darwin_arm64
	elif [[ $target_arch == amd64 ]]; then
		echo "Building binaries for darwin amd64"
		build_darwin_amd64
	else
		echo "Not support targer $target_arch"
		exit 2
	fi
}

main "$@"
