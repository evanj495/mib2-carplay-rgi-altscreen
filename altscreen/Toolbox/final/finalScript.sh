#!/bin/ksh

echo "MU1320 Toolbox SWDL bootstrap v2"
echo "HW=${1:-unknown}"
echo "SWDL_MEDIUM_ARG=${2:-<empty>}"

MMX_VOLUME=""

echo "STAGE=MMX_SD_DISCOVERY"

for candidate in /fs/sda0 /fs/sda1 /fs/sdb0 /fs/sdb1
do
    on -f mmx /bin/ksh -c \
        "[ -f '$candidate/Toolbox/scripts/update_toolbox.sh' ] &&
         [ -f '$candidate/Toolbox/scripts/install_mmi_cockpit_carplay_rx.sh' ] &&
         [ -f '$candidate/Toolbox/GEM/mqb-carplayAltScreen.esd' ]" \
         >/dev/null 2>&1

    if [ "$?" -eq 0 ]; then
        MMX_VOLUME="$candidate"
        break
    fi
done

if [ -z "$MMX_VOLUME" ]; then
    echo "FAIL_STAGE=MMX_SD_DISCOVERY"
    echo "FAIL: AltScreen Toolbox SD not visible from MMX"
    exit 21
fi

echo "MMX_VOLUME=$MMX_VOLUME"
echo "STAGE=INSTALL_TOOLBOX_FILES"

on -f mmx /bin/ksh -c '
VOLUME="$1"
TARGET=/mnt/app/eso/hmi/engdefs
SCRIPTS="$TARGET/scripts/mqb"

fail()
{
    code="$1"
    stage="$2"
    echo "FAIL_STAGE=$stage"
    mount -ur /mnt/app >/dev/null 2>&1 || true
    exit "$code"
}

echo "MMX_STAGE=MOUNT_APP_RW"
mount -uw /mnt/app || fail 22 MOUNT_APP_RW

echo "MMX_STAGE=CREATE_SCRIPT_DIR"
mkdir -p "$SCRIPTS" || fail 23 CREATE_SCRIPT_DIR

echo "MMX_STAGE=COPY_SCRIPTS"
cp "$VOLUME"/Toolbox/scripts/*.sh "$SCRIPTS"/ ||
    fail 24 COPY_SCRIPTS

echo "MMX_STAGE=CHMOD_SCRIPTS"
chmod 755 "$SCRIPTS" "$SCRIPTS"/*.sh ||
    fail 25 CHMOD_SCRIPTS

echo "MMX_STAGE=COPY_GEM"
cp "$VOLUME"/Toolbox/GEM/*.esd "$TARGET"/ ||
    fail 26 COPY_GEM

echo "MMX_STAGE=VERIFY"

[ -s "$SCRIPTS/update_toolbox.sh" ] ||
    fail 27 VERIFY_UPDATE_TOOLBOX

[ -s "$SCRIPTS/install_mmi_cockpit_carplay_rx.sh" ] ||
    fail 28 VERIFY_CARPLAY_INSTALLER

[ -s "$TARGET/mqb-carplayAltScreen.esd" ] ||
    fail 29 VERIFY_CARPLAY_MENU

echo "SCRIPT_INSTALL=PASS"
echo "CARPLAY_MENU_INSTALL=PASS"

# Preserve the upstream Toolbox cleanup for installations that may still
# contain pre-v4.1 GEM definitions or PhoneCustomer scripts.
echo "MMX_STAGE=CLEAN_LEGACY_TOOLBOX"
rm -rf "$TARGET"/mqbcoding.esd* ||
    fail 30 CLEAN_LEGACY_GEM
rm -f /mnt/app/eso/bin/PhoneCustomer/*.sh ||
    fail 30 CLEAN_LEGACY_PHONECUSTOMER
rm -f /mnt/app/eso/bin/PhoneCustomer/default/*.sh ||
    fail 30 CLEAN_LEGACY_PHONECUSTOMER_DEFAULT
rm -rf /mnt/app/eso/bin/PhoneCustomer/default/scripts ||
    fail 30 CLEAN_LEGACY_PHONECUSTOMER_SCRIPTS

echo "MMX_STAGE=MOUNT_APP_RO"
mount -ur /mnt/app || exit 30

exit 0
' toolbox_install "$MMX_VOLUME"

RC=$?

if [ "$RC" -ne 0 ]; then
    echo "FAIL_STAGE=MMX_INSTALL"
    echo "MMX_INSTALL_RC=$RC"
    exit "$RC"
fi

echo "MMX_INSTALL=PASS"

# Match upstream Toolbox behavior: request developer mode after the
# installation has already been verified. A non-zero pc return code is
# therefore diagnostic and must not turn an otherwise valid SWDL into
# a fatal installation error.
export LD_LIBRARY_PATH=/mnt/app/root/lib-target:/eso/lib:/mnt/app/usr/lib:/mnt/app/armle/lib:/mnt/app/armle/lib/dll:/mnt/app/armle/usr/lib
export IPL_CONFIG_DIR=/etc/eso/production

on -f mmx /mnt/app/eso/bin/apps/pc b:0:0xC002000D 1 \
    >/dev/null 2>&1
PC_RC=$?

echo "DEVELOPER_MODE_PC_RC=$PC_RC"

touch /tmp/SWDLScript.Result || {
    echo "FAIL_STAGE=RESULT_MARKER"
    exit 31
}

echo "TOOLBOX_SWDL_INSTALL=PASS"
echo "Done."
exit 0
