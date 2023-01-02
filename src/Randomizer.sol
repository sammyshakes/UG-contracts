// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

contract Randomizer{
    function getSeeds(uint256 rand1, uint256 rand2, uint256 numRands) external view returns (uint256[] memory) {
        uint256[] memory randNums = new uint256[](numRands);
        for(uint i; i < numRands; i++){
            randNums[i] = uint256(
                            keccak256(
                                abi.encodePacked(
                                    // solhint-disable-next-line
                                    block.timestamp,
                                    msg.sender,
                                    blockhash(block.number-1),
                                    rand1+i,
                                    rand2+i
                                )
                            )
            );
        }
        return randNums;
    }
}