"""OoT 1.1.1 trainer hooks."""

BUILD_ID = "e0f3ccfaf50065ae4ea01eb5aeb13b1a45da3348"

# The horse loads its configured number of spurs. The mounted action uses a
# signed halfword at +0x27c and publishes it to the HUD as GameData 0x3514b108.
# The timer loads the step it later subtracts from, or adds to, MiniGame_TimerValue.
SITES = (
    (0x82726f38, (0xb9403917, 0xbd423aa0, 0x1e202008), "hos_oot_trainer_horse"),
    (0x832cdd00, (0xbd400269, 0x52843117, 0xd10063a1), "hos_oot_trainer_clock"),
    # The scalar Int commit loop has loaded the pending record's GameData hash into w12.
    (0x80bb9b30, (0xb940052c, 0x340004ac, 0xf940728d), "hos_oot_trainer_target_score"),
    # Free play has populated the twelve repertoire bytes and is about to query the custom song.
    (0x832b3848, (0x3909be68, 0x97f649b5, 0x12000008), "hos_oot_trainer_songs"),
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
