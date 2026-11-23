"""OoT 1.1.1 trainer hooks."""

BUILD_ID = "e0f3ccfaf50065ae4ea01eb5aeb13b1a45da3348"

# The horse loads its configured number of spurs. The mounted action uses a
# signed halfword at +0x27c and publishes it to the HUD as GameData 0x3514b108.
# The timer loads the step it later subtracts from, or adds to, MiniGame_TimerValue.
SITES = (
    # One resolved external hit, immediately before the atomic add to the victim’s damage total.
    (0x804a99f8, (0x91006289, 0xb8280128, 0x295c2688), "hos_oot_trainer_attack"),
    (0x82726f38, (0xb9403917, 0xbd423aa0, 0x1e202008), "hos_oot_trainer_horse"),
    (0x832cdd00, (0xbd400269, 0x52843117, 0xd10063a1), "hos_oot_trainer_clock"),
    # The scalar Int commit loop has loaded the pending record's GameData hash into w12.
    (0x80bb9b30, (0xb940052c, 0x340004ac, 0xf940728d), "hos_oot_trainer_target_score"),
    # Free play has populated all thirteen repertoire bytes, including the custom song.
    (0x832b3854, (0x3909c268, 0x14000009, 0x910b7268), "hos_oot_trainer_songs"),
    # The player's accessory factory has just read the equipped actor name.
    (0x82e17394, (0xf85a83a1, 0x360001c0, 0x39400028), "hos_oot_trainer_ocarina"),
)


def install(lifter, img, build_id):
    if build_id != BUILD_ID:
        return
    for address, words, function in SITES:
        if any(img.word(address + 4 * i) != word for i, word in enumerate(words)):
            raise ValueError("trainer instruction mismatch at %#x" % address)
        hook = "{ extern void %s(Ctx *); %s(c); }" % (function, function)
        lifter.after[address] = (lifter.after.get(address, "") + "\n" + hook).strip()

    # The bottle grant just read the fifth IsValid bit. Resume the native award
    # with an existing empty slot only when all five are owned and this is the letter.
    address = 0x8112f5e0
    if (img.word(address), img.word(address + 4), img.word(0x81130798)) != (
            0x385883a8, 0x3600ad28, 0xa94923f3):
        raise ValueError("Ruto letter bottle award instruction mismatch")
    lifter.after[address] = """{ extern int hos_oot_empty_bottle_for_letter(uint64_t, uint64_t);
        if (c->x[8] & 1) {
            int slot = hos_oot_empty_bottle_for_letter(c->x[24], recomp_load64(c, c->x[31] + 0x98));
            if (slot >= 0) { c->x[21] = (unsigned)slot; goto L_81130798; }
        } }"""

    # The pickup eligibility check asks about the fifth bottle before it lets
    # the world actor start the award. Use the same rule on both sides.
    address = 0x80a95694
    if (img.word(address), img.word(address + 4), img.word(0x80a9570c)) != (
            0xaa1503e0, 0x9400065a, 0xb4000074):
        raise ValueError("Ruto letter bottle capacity instruction mismatch")
    lifter.after[address] = """{ extern int hos_oot_empty_bottle_for_letter(uint64_t, uint64_t);
        if (hos_oot_empty_bottle_for_letter(c->x[23], recomp_load64(c, c->x[24])) >= 0)
            goto L_80a9570c; }"""
