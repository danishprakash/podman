#!/usr/bin/env bats   -*- bats -*-
#
# tests for podman load
#

load helpers
load helpers.network

function teardown() {
    # Destroy all images, to make sure we don't leave garbage behind.
    #
    # The tests in here do funky things with image store, including
    # reloading the default $IMAGE in a way that appears normal but
    # is not actually the same as what is normally pulled, e.g.,
    # annotations and image digests may be different. See
    # https://github.com/containers/podman/discussions/17911
    run_podman rmi -a -f
    _prefetch $IMAGE

    basic_teardown
}

# Custom helpers for this test only. These just save us having to duplicate
# the same thing four times (two tests, each with -i and stdin).
#
# initialize, read image ID, image config digest, and name
get_img_ids_and_name() {
    run_podman images -a --format '{{.ID}} {{.Repository}}:{{.Tag}}'
    read iid img_name <<<"$output"
    img_config_digest=$(image_config_digest "@$iid")

    archive=$PODMAN_TMPDIR/myimage-$(random_string 8).tar
}

# Simple verification of image config digest and name
verify_img_config_digest_and_name() {
    run_podman images -a --format '{{.ID}} {{.Repository}}:{{.Tag}}'
    read new_iid new_img_name < <(echo "$output")
    new_img_config_digest=$(image_config_digest "@$new_iid")

    # Verify
    is "$new_img_config_digest" "$img_config_digest" "Image config digest of loaded image == original"
    is "$new_img_name"          "$1"                 "Name & tag of restored image"
}

@test "podman load invalid file" {
    # Regression test for #9672 to make sure invalid input yields errors.
    invalid=$PODMAN_TMPDIR/invalid
    echo "I am an invalid file and should cause a podman-load error" > $invalid
    run_podman 125 load -i $invalid
    # podman and podman-remote emit different messages; this is a common string
    is "$output" ".*payload does not match any of the supported image formats:.*" \
       "load -i INVALID fails with expected diagnostic"
}

@test "podman save to pipe and load" {
    # Generate a random name and tag (must be lower-case)
    local random_name=x0$(random_string 12 | tr A-Z a-z)
    local random_tag=t0$(random_string 7 | tr A-Z a-z)
    local fqin=localhost/$random_name:$random_tag
    run_podman tag $IMAGE $fqin

    # Believe it or not, 'podman load' would barf if any path element
    # included a capital letter
    archive=$PODMAN_TMPDIR/MySubDirWithCaps/MyImage-$(random_string 8).tar
    mkdir -p $(dirname $archive)

    # We can't use run_podman because that uses the BATS 'run' function
    # which redirects stdout and stderr. Here we need to guarantee
    # that podman's stdout is a pipe, not any other form of redirection
    $PODMAN save --format oci-archive $fqin | cat >$archive
    assert "$?" -eq 0 "Command failed: podman save ... | cat"

    # Make sure we can reload it
    run_podman rmi $fqin
    run_podman load -i $archive

    # FIXME: cannot compare IID, see #7371, so we check only the tag
    run_podman images $fqin --format '{{.Repository}}:{{.Tag}}'
    is "${lines[0]}" "$fqin" "image preserves name across save/load"

    # Clean up
    run_podman rmi $fqin
}

@test "podman image scp transfer" {
    skip_if_remote "only applicable under local podman"

    # See https://github.com/containers/podman/pull/21300 for details
    if [[ "$CI_DESIRED_DATABASE" = "boltdb" ]]; then
        skip "impossible due to pitfalls in our SSH implementation"
    fi

    # FIXME: Broken on debian SID; still broken 2024-09-11
    # See https://github.com/containers/podman/pull/23020#issuecomment-2179284640
    OS_RELEASE_ID="${OS_RELEASE_ID:-$(source /etc/os-release; echo $ID)}"
    if [[ "$OS_RELEASE_ID" == "debian" ]]; then
        skip "broken warning about cgroup-manager=systemd and enabling linger"
    fi

    # The testing is the same whether we're root or rootless; all that
    # differs is the destination (not-me) username.
    if is_rootless; then
        # Simple: push to root.
        whoami=$(id -un)
        notme=root
        _sudo() { command sudo -n "$@"; }
    else
        # Harder: our CI infrastructure needs to define this & set up the acct
        whoami=root
        notme=${PODMAN_ROOTLESS_USER}
        if [[ -z "$notme" ]]; then
            skip "To run this test, set PODMAN_ROOTLESS_USER to a safe username"
        fi
        _sudo() { command sudo -n -u "$notme" "$@"; }
    fi

    # If we can't sudo, we can't test.
    _sudo true || skip "cannot sudo to $notme"

    # Preserve digest of original image; we will compare against it later
    run_podman image inspect --format '{{.RepoDigests}}' $IMAGE
    src_digests=$output

    # image name that is not likely to exist in the destination
    newname=foo.bar/nonesuch/c_$(random_string 10 | tr A-Z a-z):mytag
    run_podman tag $IMAGE $newname

    # Copy it there.
    run_podman image scp $newname ${notme}@localhost::
    is "$output" "Copying blob .*Copying config.*Writing manifest"

    # confirm that image was copied. FIXME: also try $PODMAN image inspect?
    _sudo $PODMAN image exists $newname

    # Copy it back, this time using -q
    run_podman untag $IMAGE $newname
    run_podman image scp -q ${notme}@localhost::$newname

    expect="Loaded image: $newname"
    is "$output" "$expect" "-q silences output"

    # Confirm that we have it, and that its digest matches our original
    run_podman image inspect --format '{{.Digest}}' $newname
    assert "$output" =~ "$src_digests" "Digest of re-fetched image is in list of original image digests"

    # test tagging capability
    run_podman untag $IMAGE $newname
    run_podman image scp ${notme}@localhost::$newname foobar:123

    run_podman image inspect --format '{{.Digest}}' foobar:123
    assert "$output" =~ "$src_digest" "Digest of re-fetched image is in list of original image digests"

    # remove root img for transfer back with another name
    _sudo $PODMAN image rm $newname

    # get foobar's ID, for an ID transfer test
    run_podman image inspect --format '{{.ID}}' foobar:123
    run_podman image scp $output ${notme}@localhost::foobartwo

    _sudo $PODMAN image exists foobartwo

    # Clean up
    _sudo $PODMAN image rm foobartwo
    run_podman untag $IMAGE $newname

    # Negative test for nonexistent image.
    # FIXME: error message is 2 lines, the 2nd being "exit status 125".
    # FIXME: is that fixable, or do we have to live with it?
    nope="nope.nope/nonesuch:notag"
    run_podman 125 image scp ${notme}@localhost::$nope
    is "$output" "Error: $nope: image not known.*" "Pulling nonexistent image"

    run_podman 125 image scp $nope ${notme}@localhost::
    is "$output" "Error: $nope: image not known.*" "Pushing nonexistent image"

    run_podman rmi foobar:123
}


@test "podman load - by image ID" {
    # FIXME: how to build a simple archive instead?
    get_img_ids_and_name

    # Save image by ID, and remove it.
    run_podman save $iid -o $archive
    run_podman rmi $iid

    # Load using -i; IID should be preserved, but name is not.
    run_podman load -i $archive
    verify_img_config_digest_and_name "<none>:<none>"

    # Same as above, using stdin
    run_podman rmi $iid
    run_podman load < $archive
    verify_img_config_digest_and_name "<none>:<none>"

    # Same as above, using stdin but with `podman image load`
    run_podman rmi $iid
    run_podman image load < $archive
    verify_img_config_digest_and_name "<none>:<none>"
}

@test "podman load - by image name" {
    get_img_ids_and_name
    run_podman save $img_name -o $archive
    run_podman rmi $iid

    # Load using -i; this time the image should be tagged.
    run_podman load -i $archive
    verify_img_config_digest_and_name $img_name
    run_podman rmi $iid

    # Also make sure that `image load` behaves the same.
    run_podman image load -i $archive
    verify_img_config_digest_and_name $img_name
    run_podman rmi $iid

    # Same as above, using stdin
    run_podman load < $archive
    verify_img_config_digest_and_name $img_name
}

@test "podman load - from URL" {
    get_img_ids_and_name
    run_podman save $img_name -o $archive
    run_podman rmi $iid

    HOST_PORT=$(random_free_port)
    SERVER=http://127.0.0.1:$HOST_PORT

    # Bind-mount the archive to a container running httpd
    run_podman run -d --name myweb -p "$HOST_PORT:80" \
            -v $archive:/var/www/image.tar:Z \
            -w /var/www \
            $IMAGE /bin/busybox-extras httpd -f -p 80
    # We now have $IMAGE pointing at the image, possibly using a zstd:chunked (TOC-based) pull
    run_podman load -i $SERVER/image.tar

    # This should move the $img_name tag ( = $IMAGE) to the result of loading the image;
    # this is a non-TOC-based load, so it might or might not deduplicate the loaded image with
    # the one for myweb.
    # So, if we have an untagged image, it’s probably the one for myweb, and try to remove it.
    run_podman rm -f -t0 myweb
    run_podman images -a --format '{{.ID}} {{.Repository}}:{{.Tag}}'
    local myweb_iid=$(echo "$output" | sed -n '/<none>:<none>/s/ .*$//p')
    if [[ -n "$myweb_iid" ]]; then
        run_podman rmi $myweb_iid
    fi

    verify_img_config_digest_and_name $img_name
}

@test "podman load - redirect corrupt payload" {
    run_podman 125 load <<< "Danger, Will Robinson!! This is a corrupt tarball!"
    is "$output" \
        ".*payload does not match any of the supported image formats:.*" \
        "Diagnostic from 'podman load' unknown/corrupt payload"
}

@test "podman load - multi-image archive" {
    # img1 & 2 should be images that are not locally present; they must also
    # be usable on the host arch. The nonlocal image (:000000xx) is kept
    # up-to-date for all RHEL/Fedora arches; the other image we use is
    # the one tagged ':multiimage', which as of 2021-07-15 is :20210610
    # but that tag will grow stale over time. If/when this test fails,
    # your first approach should be to manually update :multiimage to
    # point to a more recent testimage. (Use the quay.io GUI, it's waaay
    # easier than pulling/pushing the correct manifest.)
    img1=${PODMAN_NONLOCAL_IMAGE_FQN}
    img2="$PODMAN_TEST_IMAGE_REGISTRY/$PODMAN_TEST_IMAGE_USER/$PODMAN_TEST_IMAGE_NAME:multiimage"
    archive=$PODMAN_TMPDIR/myimage-$(random_string 8).tar

    _prefetch $img1
    _prefetch $img2

    run_podman save -m -o $archive $img1 $img2
    run_podman rmi -f $img1 $img2
    run_podman load -i $archive

    run_podman image exists $img1
    run_podman image exists $img2
    run_podman rmi -f $img1 $img2
}

@test "podman load - multi-image archive with redirect" {
    # (see comments in test above re: img1 & 2)
    img1=${PODMAN_NONLOCAL_IMAGE_FQN}
    img2="$PODMAN_TEST_IMAGE_REGISTRY/$PODMAN_TEST_IMAGE_USER/$PODMAN_TEST_IMAGE_NAME:multiimage"
    archive=$PODMAN_TMPDIR/myimage-$(random_string 8).tar

    _prefetch $img1
    _prefetch $img2

    # We can't use run_podman because that uses the BATS 'run' function
    # which redirects stdout and stderr. Here we need to guarantee
    # that podman's stdout is a pipe, not any other form of redirection
    $PODMAN save -m $img1 $img2 | cat >$archive
    assert "$?" -eq 0 "Command failed: podman save ... | cat"

    run_podman rmi -f $img1 $img2
    run_podman load -i $archive

    run_podman image exists $img1
    run_podman image exists $img2
    run_podman rmi -f $img1 $img2
}

@test "podman save --oci-accept-uncompressed-layers" {
    archive=$PODMAN_TMPDIR/myimage-$(random_string 8).tar
    untar=$PODMAN_TMPDIR/myuntar-$(random_string 8)
    mkdir -p $untar

    # Create a tarball, unpack it and make sure the layers are uncompressed.
    run_podman save -o $archive --format oci-archive --uncompressed $IMAGE
    tar -C $untar -xvf $archive
    run file $untar/blobs/sha256/*
    is "$output" ".*POSIX tar archive" "layers are uncompressed"
}

# vim: filetype=sh
