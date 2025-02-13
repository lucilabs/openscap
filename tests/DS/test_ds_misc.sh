#!/usr/bin/env bash

# Author:
#   Martin Preisler <mpreisle@redhat.com>

set -e -o pipefail

. $builddir/tests/test_common.sh
. $srcdir/test_ds_common.sh

# Test Cases.

sds_add_multiple_twice(){
	local DIR="${srcdir}/sds_multiple_oval"
	local XCCDF_FILE="multiple-oval-xccdf.xml"
	local DS_TARGET_DIR="$(mktemp -d)"
	local DS_FILE="$DS_TARGET_DIR/sds.xml"
	local stderr=$(mktemp -t sds_add.out.XXXXXX)

	# Create DS from scratch
	pushd "$DIR"
	$OSCAP ds sds-compose "$XCCDF_FILE" "$DS_FILE" 2>&1 > $stderr
	diff $stderr /dev/null
	popd

	# Add the very same XCCDF file again with two OVAL files
	local ADD_DIR="$(mktemp -d)"
	cp ${DIR}/*.xml ${ADD_DIR}
	chmod u+w ${ADD_DIR}/* # distcheck shall be able to unlink these files (without --force)
	local XCCDF2="$ADD_DIR/$XCCDF_FILE"
	pushd ${ADD_DIR}
	$OSCAP ds sds-add "$XCCDF2" "$DS_FILE" 2>&1 > $stderr
	local ifiles=$(ls *.xml)
	popd
	diff $stderr /dev/null
	rm $XCCDF2 ${ADD_DIR}/*-oval.xml
	rm -f ${ADD_DIR}/oscap_debug.log.*
	rmdir ${ADD_DIR}

	$OSCAP ds sds-validate "$DS_FILE" 2>&1 > $stderr
	diff $stderr /dev/null
	assert_correct_xlinks "$DS_FILE"
	$OSCAP info "$DS_FILE" 2> $stderr
	diff $stderr /dev/null

	local result=$DS_FILE
	assert_exists 1 '/ds:data-stream-collection/ds:data-stream'
	assert_exists 2 '/ds:data-stream-collection/ds:data-stream/*'
	assert_exists 1 '/ds:data-stream-collection/ds:data-stream/ds:checklists'
	assert_exists 2 '/ds:data-stream-collection/ds:data-stream/ds:checklists/*'
	assert_exists 2 '/ds:data-stream-collection/ds:data-stream/ds:checklists/ds:component-ref'
	assert_exists 1 '/ds:data-stream-collection/ds:data-stream/ds:checks'
	assert_exists 4 '/ds:data-stream-collection/ds:data-stream/ds:checks/*'
	assert_exists 4 '/ds:data-stream-collection/ds:data-stream/ds:checks/ds:component-ref'
	assert_exists 6 '/ds:data-stream-collection/ds:component'
	assert_exists 4 '/ds:data-stream-collection/ds:component/oval_definitions'
	assert_exists 2 '/ds:data-stream-collection/ds:component/xccdf:Benchmark'

	# split the SDS and verify the content
	pushd "$DS_TARGET_DIR"
	$OSCAP ds sds-split "`basename $DS_FILE`" "$DS_TARGET_DIR"
	[ ! -f multiple-oval-xccdf.xml ]
	mv scap_org.open-scap_cref_multiple-oval-xccdf.xml multiple-oval-xccdf.xml
	popd
	local f
	for f in second-oval.xml first-oval.xml multiple-oval-xccdf.xml; do
		$OSCAP info ${DS_TARGET_DIR}/$f 2> $stderr
		diff $stderr /dev/null
		diff ${DS_TARGET_DIR}/$f ${DIR}/$f
		rm ${DS_TARGET_DIR}/$f
	done
	rm $DS_FILE
	rm -f $DS_TARGET_DIR/oscap_debug.log.*
	rmdir $DS_TARGET_DIR
	rm $stderr
}

function test_eval {
    probecheck "rpminfo" || return 255
    local stderr=$(mktemp -t ${name}.out.XXXXXX)
    $OSCAP xccdf eval "${srcdir}/$1" 2> $stderr
    diff /dev/null $stderr; rm $stderr
}

function test_eval_cpe {
    local stdout=$(mktemp -t ${name}.out.XXXXXX)
    local stderr=$(mktemp -t ${name}.err.XXXXXX)
    local ret=0

    $OSCAP xccdf eval --progress "${srcdir}/$1" 1> $stdout 2> $stderr || ret=$?
    grep -q "rule_applicable_pass:pass" $stdout
    grep -q "rule_applicable_fail:fail" $stdout
    grep -q "rule_notapplicable:notapplicable" $stdout
    diff /dev/null $stderr
    rm $stdout $stderr
}

function test_invalid_eval {
    local ret=0
    $OSCAP xccdf eval "${srcdir}/$1" || ret=$?
    return $([ $ret -eq 1 ])
}

function test_invalid_oval_eval {
    local ret=0
    $OSCAP oval eval "${srcdir}/$1" || ret=$?
    return $([ $ret -eq 1 ])
}

function test_eval_id {

    OUT=$($OSCAP xccdf eval --datastream-id $2 --xccdf-id $3 "${srcdir}/$1")
    local RET=$?

    if [ $RET -ne 0 ]; then
        return 1
    fi

    echo "$OUT" | grep $4 > /dev/null
}

function test_eval_benchmark_id {

    OUT=$($OSCAP xccdf eval --benchmark-id $2 "${srcdir}/$1")
    local RET=$?

    if [ $RET -ne 0 ]; then
        return 1
    fi

    echo "$OUT" | grep $3 > /dev/null
}

function test_eval_complex()
{
	local name=${FUNCNAME}
	local arf=$(mktemp -t ${name}.arf.XXXXXX)
	local stderr=$(mktemp -t ${name}.err.XXXXXX)
	local stdout=$(mktemp -t ${name}.out.XXXXXX)

	$OSCAP xccdf eval \
		--results-arf $arf \
		--datastream-id scap_org.open-scap_datastream_tst2 \
		--xccdf-id scap_org.open-scap_cref_second-xccdf.xml2 \
		--profile xccdf_moc.elpmaxe.www_profile_2 \
		$srcdir/eval_xccdf_id/sds-complex.xml 2> $stderr > $stdout

	# Ensure the sanity of the output.
	[ -f $stderr ]; [ ! -s $stderr ]
	[ "`grep ^Rule $stdout | wc -l`" == "1" ]
	grep ^Rule $stdout | grep xccdf_moc.elpmaxe.www_rule_secon
	rm $stdout

	# Ensure basic correctness of the ARF
	$OSCAP ds rds-validate $arf 2>&1 > $stderr
	[ -f $srderr ]; [ ! -s $stderr ]; rm $stderr
	assert_correct_xlinks $arf

	# Ensure that results are there
	local result="$arf"
	assert_exists 1 '//rule-result'
	assert_exists 1 '//rule-result[@idref="xccdf_moc.elpmaxe.www_rule_second"]'
	assert_exists 1 '//rule-result/result'
	assert_exists 1 '//rule-result/result[text()="pass"]'
	assert_exists 1 '//TestResult/benchmark[@href="#scap_org.open-scap_comp_second-xccdf.xml2"]'
	rm $arf
}

function test_oval_eval {

    $OSCAP oval eval "${srcdir}/$1"
}

function test_oval_eval_id {

    OUT=$($OSCAP oval eval --datastream-id $2 --oval-id $3 "${srcdir}/$1")
    local RET=$?

    if [ $RET -ne 0 ]; then
        return 1
    fi
    echo "out: $OUT"

    echo "$OUT" | grep $4 > /dev/null
}

function test_sds_external_xccdf_in_ds {
    local SDS_FILE="${srcdir}/sds_external_xccdf/sds.ds.xml"
    local XCCDF="scap_org.open-scap_cref_xccdf.xml"
    local PROFILE="xccdf_external_profile_datastream_1"
    local result="$(mktemp)"

    $OSCAP xccdf eval --xccdf-id "$XCCDF" --profile "$PROFILE" --results-arf "$result" "$SDS_FILE"

    assert_exists 1 '//rule-result/result[text()="pass"]'
    assert_exists 1 '//TestResult/benchmark[@href="file:xccdf.sds.xml#scap_1_comp_xccdf.xml"]'

    rm -f "$result"
}

function test_sds_external_xccdf {
    local SDS_FILE="${srcdir}/sds_external_xccdf/sds.ds.xml"
    local XCCDF="scap_org.open-scap_cref_xccdf-file.xml"
    local PROFILE="xccdf_external_profile_file_1"
    local result="$(mktemp)"

    $OSCAP xccdf eval --xccdf-id "$XCCDF" --profile "$PROFILE" --results-arf "$result" "$SDS_FILE"

    assert_exists 1 '//rule-result/result[text()="pass"]'
    assert_exists 1 '//TestResult/benchmark[@href="file:xccdf.xml"]'

    rm -f "$result"
}

function test_sds_tailoring {
	local SDS_FILE="${srcdir}/$2"
	local DATASTREAM_ID="$3"
	local TAILORING_ID="$4"
	local PROFILE="$5"
	local result=$(mktemp)

	$OSCAP info "$SDS_FILE"

	$OSCAP xccdf eval --datastream-id "$DATASTREAM_ID" --tailoring-id "$TAILORING_ID" --profile "$PROFILE" --results "$result" "$SDS_FILE"

	assert_exists 2 '//Rule'
	assert_exists 1 '//Rule[@id="xccdf_com.example_rule_1" and @selected="true"]'
	assert_exists 1 '//Rule[@id="xccdf_com.example_rule_2" and @selected="false"]'
	assert_exists 2 '//rule-result'
	assert_exists 1 '//rule-result[@idref="xccdf_com.example_rule_1"]'
	assert_exists 1 '//rule-result[@idref="xccdf_com.example_rule_2"]'
	assert_exists 1 '//rule-result[@idref="xccdf_com.example_rule_1"]/result[text()="notselected"]'
	assert_exists 1 '//rule-result[@idref="xccdf_com.example_rule_2"]/result[text()="pass"]'

	rm -f "$result"
}

function test_ds_continue_without_remote_resources() {
	local DS="${srcdir}/$1"
	local PROFILE="$2"
	local result=$(mktemp)
	local oval_result="test_single_rule.oval.xml.result.xml"

	$OSCAP xccdf eval --oval-results --profile "$PROFILE" --results "$result" "$DS"

	assert_exists 1 '//rule-result[@idref="xccdf_com.example.www_rule_test-pass"]/result[text()="pass"]'
	assert_exists 1 '//rule-result[@idref="xccdf_com.example.www_rule_test-remote_res"]/result[text()="notchecked"]'
	assert_exists 1 '//rule-result[@idref="xccdf_com.example.www_rule_test-pass2"]/result[text()="pass"]'

	rm -f "$result" "$oval_result"
}

function test_ds_error_remote_resources() {
	local DS="${srcdir}/$1"
	local PROFILE="$2"
	local result=$(mktemp)
	local stderr=$(mktemp)

	$OSCAP xccdf eval --fetch-remote-resources --profile "$PROFILE" --results "$result" "$DS" 2>"$stderr" || ret=$?
	grep -q "Downloading: https://www.example.com/security/data/oval/oval.xml.bz2 ... error" "$stderr"
	grep -q "OpenSCAP Error: Download failed: HTTP response code said error: 404" "$stderr"

	rm -f "$result" "$stderr"
}

function test_source_date_epoch() {
	local xccdf="$srcdir/sds_multiple_oval/multiple-oval-xccdf.xml"
	local result="$(mktemp)"
	local timestamp="2020-03-05T12:09:37"
	export SOURCE_DATE_EPOCH="1583410177"
	export TZ=UTC
	# ensure the file mtime is always newer than the $timestamp
	touch -c "$srcdir/sds_multiple_oval/first-oval.xml"
	touch -c "$srcdir/sds_multiple_oval/multiple-oval-xccdf.xml"
	touch -c "$srcdir/sds_multiple_oval/second-oval.xml"
	$OSCAP ds sds-compose "$xccdf" "$result"
	assert_exists 3 '//ds:component[@timestamp="'$timestamp'"]'
	rm -f "$result"
}


# Testing.
test_init

test_run "sds_external_xccdf_in_ds" test_sds_external_xccdf_in_ds
test_run "sds_external_xccdf" test_sds_external_xccdf
test_run "sds_tailoring" test_sds_tailoring sds_tailoring sds_tailoring/sds.ds.xml scap_com.example_datastream_with_tailoring xccdf_com.example_cref_tailoring_01 xccdf_com.example_profile_tailoring

test_run "eval_simple" test_eval eval_simple/sds.xml
test_run "cpe_in_ds" test_eval cpe_in_ds/sds.xml
test_run "eval_invalid" test_invalid_eval eval_invalid/sds.xml
test_run "eval_invalid_oval" test_invalid_oval_eval eval_invalid/sds-oval.xml
test_run "eval_xccdf_id1" test_eval_id eval_xccdf_id/sds.xml scap_org.open-scap_datastream_tst scap_org.open-scap_cref_first-xccdf.xml first
test_run "eval_xccdf_id2" test_eval_id eval_xccdf_id/sds.xml scap_org.open-scap_datastream_tst scap_org.open-scap_cref_second-xccdf.xml second
test_run "eval_benchmark_id1" test_eval_benchmark_id eval_xccdf_id/sds.xml xccdf_moc.elpmaxe.www_benchmark_first first
test_run "eval_benchmark_id2" test_eval_benchmark_id eval_xccdf_id/sds.xml xccdf_moc.elpmaxe.www_benchmark_second second
test_run "eval_benchmark_id_conflict" test_eval_benchmark_id eval_benchmark_id_conflict/sds.xml xccdf_moc.elpmaxe.www_benchmark_first first
test_run "eval_just_oval" test_oval_eval eval_just_oval/sds.xml
test_run "eval_oval_id1" test_oval_eval_id eval_oval_id/sds.xml scap_org.open-scap_datastream_just_oval scap_org.open-scap_cref_scap-oval1.xml "oval:x:def:1"
test_run "eval_oval_id2" test_oval_eval_id eval_oval_id/sds.xml scap_org.open-scap_datastream_just_oval scap_org.open-scap_cref_scap-oval2.xml "oval:x:def:2"
test_run "eval_cpe" test_eval_cpe eval_cpe/sds.xml

test_run "test_eval_complex" test_eval_complex
test_run "sds_add_multiple_oval_twice_in_row" sds_add_multiple_twice
test_run "test_ds_1_2_continue_without_remote_resources" test_ds_continue_without_remote_resources ds_continue_without_remote_resources/remote_content_1.2.ds.xml xccdf_com.example.www_profile_test_remote_res
test_run "test_ds_1_2_error_remote_resources" test_ds_error_remote_resources ds_continue_without_remote_resources/remote_content_1.2.ds.xml xccdf_com.example.www_profile_test_remote_res
test_run "test_ds_1_3_continue_without_remote_resources" test_ds_continue_without_remote_resources ds_continue_without_remote_resources/remote_content_1.3.ds.xml xccdf_com.example.www_profile_test_remote_res
test_run "test_ds_1_3_error_remote_resources" test_ds_error_remote_resources ds_continue_without_remote_resources/remote_content_1.3.ds.xml xccdf_com.example.www_profile_test_remote_res
test_run "test_source_date_epoch" test_source_date_epoch

test_exit

