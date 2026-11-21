"""OoT 1.1.1 horse stamina and timed challenge updates."""

BUILD_ID = "e0f3ccfaf50065ae4ea01eb5aeb13b1a45da3348"

# The horse loads its configured number of spurs. The mounted action uses a
# signed halfword at +0x27c and publishes it to the HUD as GameData 0x3514b108.
# The timer loads the step it later subtracts from, or adds to, MiniGame_TimerValue.
SITES = (
    (0x82726f38, (0xb9403917, 0xbd423aa0, 0x1e202008), "hos_oot_trainer_horse"),
    (0x832cdd00, (0xbd400269, 0x52843117, 0xd10063a1), "hos_oot_trainer_clock"),
)


def install(lifter, img, build_id):
    if build_id != BUILD_ID:
        return
    for address, words, function in SITES:
        if any(img.word(address + 4 * i) != word for i, word in enumerate(words)):
            raise ValueError("trainer instruction mismatch at %#x" % address)
        hook = "{ extern void %s(Ctx *); %s(c); }" % (function, function)
        lifter.after[address] = (lifter.after.get(address, "") + "\n" + hook).strip()
