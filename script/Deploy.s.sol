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
import '../src/RaidEntry.sol';
import '../src/UGFightClubAlley.sol';
import '../src/UGForgeSmith.sol';

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

    address bloodOwnerTestnet = 0x5b8F11C2c1E33f0857c12Da896bF7c86A8101023;//testnet blood owner
    address bloodContractTestnet = 0x649A53b481031ff57367F672e07d0A488ad421d9;//testnet blood addy
        


    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
            //Deploy Contracts
            randomizer = Randomizer(vm.envAddress("RANDOMIZER_TESTNET_ADDRESS"));
            ugFYakuza = IUGFYakuza(vm.envAddress("UGFYAKUZA_TESTNET_ADDRESS"));
            ugNFT =  IUGNFT(vm.envAddress("UGNFT2_TESTNET_ADDRESS"));
            ugWeapons = UGWeapons(vm.envAddress("UGWEAPONS2_TESTNET_ADDRESS"));
            ugForgeSmith = UGForgeSmith(vm.envAddress("UGFORGESMITH2_TESTNET_ADDRESS"));
            uBLOOD = IUBlood(bloodContractTestnet);//testnet blood addy
            ugYakDen = new UGYakDen( address(ugFYakuza), bloodContractTestnet, bloodOwnerTestnet);
            fclubAlley = new UGFightClubAlley( address(ugNFT), bloodContractTestnet, address(randomizer), bloodOwnerTestnet);
            ugArena = new UGArena(address(ugNFT), address(ugFYakuza), bloodContractTestnet, address(randomizer), address(ugYakDen));
            
            ugRaid = new UGRaid(address(ugNFT), address(ugFYakuza), bloodContractTestnet, address(ugArena), address(ugWeapons), address(randomizer), bloodOwnerTestnet, address(ugYakDen), address(fclubAlley));
            raidEntry = new RaidEntry( address(ugFYakuza), bloodContractTestnet, address(ugArena), address(ugWeapons), address(ugRaid), address(ugYakDen), address(fclubAlley), address(bloodOwnerTestnet));

            ugGame = new UGgame(address(ugNFT),address(ugFYakuza),address(ugArena), address(ugRaid), bloodContractTestnet,  address(ugForgeSmith), bloodOwnerTestnet, address(fclubAlley));       

            ugArena.setGameContract(address(ugGame));
            ugYakDen.setGameContract(address(ugGame));
            fclubAlley.setGameContract(address(ugGame));
            //set Admins
            fclubAlley.addAdmin(address(ugGame));
            fclubAlley.addAdmin(address(ugRaid));
            fclubAlley.addAdmin(address(raidEntry));
            ugRaid.addAdmin(address(ugGame));
            ugArena.addAdmin(address(ugGame));
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

        vm.stopBroadcast();
    }
}