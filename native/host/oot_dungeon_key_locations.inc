/* OoT 1.1.1. Chest flags are IsTreasureBoxOpen.<placement ID> from the
   dungeon Banc files. Loose keys use the collection flag in their room logic. */
static const DungeonKeyPickup keys_ForestTemple[] = {
    {0x196af396u, 0xfbfd2cccu},  /* chest 7535137041266964235 */
    {0x84ee2d58u, 0xa31db95bu},  /* chest 14776684749746592758 */
    {0x9b2e155fu, 0x21b0bd71u},  /* chest 3433400840978782007 */
    {0x6f0d153fu, 0x5cb887dcu},  /* chest 6449977980406424425 */
    {0x8b9a3d0fu, 0xdaf141e8u},  /* chest 1171460703078800858 */
};
static const DungeonKeyPickup keys_FireTemple[] = {
    {0xba01b6d8u, 0xbe0be4f3u},  /* chest 12945617941305968586 */
    {0xe335247du, 0x7ba3c368u},  /* chest 16785682308850448108 */
    {0xfaa8c214u, 0x57771bbdu},  /* chest 5634724236470386190 */
    {0x946efbe1u, 0xf6544fd0u},  /* chest 3949488292768750868 */
    {0x4958d1f3u, 0xf37fa0b2u},  /* chest 10521366928524045067 */
    {0x34c864c6u, 0x6669c4ebu},  /* chest 1705064956286753527 */
    {0x586234b3u, 0x49ee141au},  /* chest 9634924691849556346 */
    {0x393759f0u, 0x24ef10ffu},  /* chest 12567412825200613393 */
};
static const DungeonKeyPickup keys_WaterTemple[] = {
    {0x8914a506u, 0x588ab25fu},  /* chest 18099019250896853049 */
    {0xb6b6070bu, 0x24d15ea2u},  /* chest 16490222392193949581 */
    {0x7ea60e52u, 0x0ec96f6du},  /* chest 3693930347660122883 */
    {0x7f4783e6u, 0xd492a7afu},  /* chest 2503861086004941173 */
};
static const DungeonKeyPickup keys_SpiritTemple[] = {
    {0xd683aa25u, 0x00000000u},  /* chest 5703423643219134246 */
    {0xc6e1ed2du, 0x00000000u},  /* chest 2203243501006528435 */
    {0x66741a95u, 0x00000000u},  /* chest 17407066694905911064 */
    {0xcdc08c75u, 0x00000000u},  /* chest 4277978357934400600 */
    {0x4e36e8cbu, 0x00000000u},  /* chest 12042193296697281461 */
};
static const DungeonKeyPickup keys_ShadowTemple[] = {
    {0x93712b23u, 0x00000000u},  /* chest 1111717451118505545 */
    {0x62789454u, 0x00000000u},  /* chest 5781953901224064730 */
    {0xd38dfe04u, 0x00000000u},  /* chest 169081039115821925 */
    {0x59d7231eu, 0x00000000u},  /* chest 17902550525792072472 */
    {0xa16d839cu, 0x00000000u},  /* room 13 loose key */
};
static const DungeonKeyPickup keys_InsideGanonCastle[] = {
    {0xf66a9af3u, 0x00000000u},  /* chest 15320975652699461295 */
};
static const DungeonKeyPickup keys_BottomOfTheWell[] = {
    {0x4ee0b514u, 0x00000000u},  /* chest 8397646530660039355 */
    {0x8028323fu, 0x136909afu},  /* room 3 loose key */
};
static const DungeonKeyPickup keys_GerudoTrainingGround[] = {
    {0x66f10fddu, 0x00000000u},  /* chest 11563468890171962383 */
    {0x2b899495u, 0x00000000u},  /* chest 3717705376223508790 */
    {0x2e46de13u, 0x00000000u},  /* chest 5329807728555596183 */
    {0x760940b1u, 0x00000000u},  /* chest 4709724720801091788 */
    {0x81ebaa2bu, 0x00000000u},  /* chest 4372363658229299619 */
    {0x7d813872u, 0x00000000u},  /* chest 4320448574091221496 */
    {0xf33d12b3u, 0x00000000u},  /* chest 9911316961118170383 */
    {0xdfa226efu, 0x00000000u},  /* chest 13501407288943710656 */
    {0xea6cde49u, 0x00000000u},  /* chest 1883068192328530224 */
};
static const DungeonKeyPickup keys_GerudoFortress[] = {
    {0xdc0010f6u, 0x00000000u},  /* carpenter cell 1 */
    {0x1ee8e249u, 0x00000000u},  /* carpenter cell 2 */
    {0x2815a352u, 0x00000000u},  /* carpenter cell 3 */
    {0x397957cau, 0x00000000u},  /* carpenter cell 4 */
};

static const DungeonKeys key_dungeons[] = {
    KEY_DUNGEON(ForestTemple, 0x90237092u, 0x8e3caa01u, 0x1ab3a75fu, 0x893e0c3au, 0x00000000u, 0x427333a0u),
    KEY_DUNGEON(FireTemple, 0x1df11487u, 0x8b3ea4e5u, 0x7d5f5e11u, 0x12a3b141u, 0x00000000u, 0xb72d73dfu),
    KEY_DUNGEON(WaterTemple, 0x877bdceeu, 0xdb94bf89u, 0x3a83324eu, 0x88b6cf77u, 0xe331f321u, 0x79daf80au),
    KEY_DUNGEON(SpiritTemple, 0x79eeec8eu, 0xe25088aau, 0xc80561f5u, 0x4f583ba3u, 0x00000000u, 0x1984c03fu),
    KEY_DUNGEON(ShadowTemple, 0x5edda9e3u, 0x134be288u, 0xa0c80bb5u, 0x4a9a8ad6u, 0x00000000u, 0xc33c66cfu),
    KEY_DUNGEON(InsideGanonCastle, 0xfbfd2910u, 0x1f251941u, 0x6decc59fu, 0xd5b8bc12u, 0x00000000u, 0x2fd59293u),
    KEY_DUNGEON(BottomOfTheWell, 0x7dd79d10u, 0x085df1c9u, 0x9e76cb62u, 0x00000000u, 0x00000000u, 0x00000000u),
    KEY_DUNGEON(GerudoTrainingGround, 0xea9786f5u, 0xb6e150c9u, 0xbdacbe20u, 0x00000000u, 0x00000000u, 0x00000000u),
    KEY_DUNGEON(GerudoFortress, 0x3a28b6a4u, 0x138e10b3u, 0x1237b28eu, 0x00000000u, 0x00000000u, 0x00000000u),
};
