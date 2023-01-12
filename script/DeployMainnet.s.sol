// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/interfaces/IUGNFT.sol";
import "../src/interfaces/IUGFYakuza.sol";
import "../src/UGYakDen.sol";
import "../src/UGRaid.sol";
import "../src/UGgame.sol";
import "../src/UGWeapons.sol";
import "../src/Randomizer.sol";
import "../src/UGArena.sol";
import "../src/RaidEntry.sol";
import "../src/UGFightClubAlley.sol";
import "../src/UGForgeSmith.sol";

contract Deploy is Script {
    // Deployments
    IUGFYakuza public ugFYakuza;
    IUGNFT public ugNFT;
    UGYakDen public ugYakDen;
    UGArena public ugArena;
    IUBlood public uBLOOD;
    UGgame public ugGame;
    UGRaid public ugRaid;
    Randomizer public randomizer;
    UGWeapons public ugWeapons;
    RaidEntry public raidEntry;
    UGFightClubAlley public fclubAlley;
    UGForgeSmith public ugForgeSmith;

    address bloodOwner = 0x715ac5FC4c4587Fa8e425Afc1D1207Cffb7b66d5; // blood owner
    address devWallet = 0x18CDFFA4D6425C3674e6085d96dE413cf4634a5d; 

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAINNET");

        //Deploy Contracts
        randomizer = Randomizer(vm.envAddress("REACT_APP_RANDOMIZER_MAINNET_ADDRESS"));
        ugFYakuza = IUGFYakuza(vm.envAddress("REACT_APP_UGFYAKUZA_MAINNET_ADDRESS"));
        ugNFT = IUGNFT(vm.envAddress("REACT_APP_UGNFT2_MAINNET_ADDRESS"));
        ugWeapons = UGWeapons(vm.envAddress("REACT_APP_UGWEAPONS2_MAINNET_ADDRESS"));
        ugForgeSmith = UGForgeSmith(
            vm.envAddress("REACT_APP_UGFORGESMITH3_MAINNET_ADDRESS")
        );
        uBLOOD = IUBlood(vm.envAddress("REACT_APP_BLOOD_MAINNET_ADDRESS")); 

        vm.startBroadcast(deployerPrivateKey);

        ugYakDen = new UGYakDen(
            address(ugFYakuza),
            address(uBLOOD),
            devWallet
        );
        fclubAlley = new UGFightClubAlley(
            address(ugNFT),
            address(uBLOOD),
            address(randomizer),
            devWallet
        );
        ugArena = new UGArena(
            address(ugNFT),
            address(ugFYakuza),
            address(uBLOOD),
            address(randomizer),
            address(ugYakDen)
        );
        ugRaid = new UGRaid(
            address(ugNFT),
            address(ugFYakuza),
            address(uBLOOD),
            address(ugArena),
            address(ugWeapons),
            address(randomizer),
            devWallet,
            address(ugYakDen),
            address(fclubAlley)
        );
        raidEntry = new RaidEntry(
            address(ugFYakuza),
            address(uBLOOD),
            address(ugArena),
            address(ugWeapons),
            address(ugRaid),
            address(ugYakDen),
            address(fclubAlley),
            address(devWallet)
        );
        ugGame = new UGgame(
            address(ugNFT),
            address(ugFYakuza),
            address(ugArena),
            address(ugRaid),
            address(uBLOOD),
            address(ugForgeSmith),
            devWallet,
            address(fclubAlley)
        );

        ugArena.setGameContract(address(ugGame));
        ugYakDen.setGameContract(address(ugGame));
        fclubAlley.setGameContract(address(ugGame));
        //set Admins
        fclubAlley.addAdmin(address(ugGame));
        fclubAlley.addAdmin(address(ugRaid));
        fclubAlley.addAdmin(address(raidEntry));
        ugRaid.addAdmin(address(ugGame));
        ugArena.addAdmin(address(ugGame));        
        ugArena.addAdmin(address(ugForgeSmith));
        ugArena.addAdmin(address(ugRaid));
        ugArena.addAdmin(address(raidEntry));
        ugYakDen.addAdmin(address(ugArena));
        ugYakDen.addAdmin(address(ugRaid));
        ugYakDen.addAdmin(address(raidEntry));

        ugNFT.addAdmin(address(ugGame));
        ugNFT.addAdmin(address(ugRaid));
        ugNFT.addAdmin(address(ugArena));

        ugFYakuza.addAdmin(address(ugGame));
        ugFYakuza.addAdmin(address(ugRaid));
        ugFYakuza.addAdmin(address(ugArena));
        ugFYakuza.addAdmin(address(ugYakDen));
        ugFYakuza.addAdmin(address(raidEntry));
        ugForgeSmith.addAdmin(address(ugGame));

        //turn on  minting
        ugGame.setAmuletMintActive(true);
        ugGame.setRingMintActive(true);
        ugGame.setForgeMintActive(true);
        ugGame.setFightClubMintActive(true);

        ugRaid.setDevWallet(devWallet);
        ugRaid.addAdmin(address(raidEntry));
        ugWeapons.addAdmin(address(ugRaid));
        ugWeapons.addAdmin(address(raidEntry));

        ugGame.setDevWallet(devWallet);

        uBLOOD.addAdmin(address(ugGame));
        uBLOOD.addAdmin(address(ugRaid));
        uBLOOD.addAdmin(address(raidEntry));
        uBLOOD.addAdmin(address(ugArena));
        uBLOOD.addAdmin(address(ugYakDen));
        uBLOOD.addAdmin(address(fclubAlley));

        //phase switches
        // ugRaid.setWeaponsRound(true);
        // ugRaid.setYakuzaRound(true);
        // ugRaid.setSweatRound(true);

        ugForgeSmith.setContracts(
            address(ugNFT), 
            address(ugFYakuza), 
            address(uBLOOD), 
            address(ugWeapons), 
            address(ugArena)
        );

        vm.stopBroadcast();
    }
}
