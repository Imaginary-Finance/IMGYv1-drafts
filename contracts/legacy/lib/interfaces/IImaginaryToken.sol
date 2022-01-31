// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IImaginaryToken {
	//mapping get function
	function lastMintingTime(address) external returns (uint256);
	function lastBurningTime(address) external returns (uint256);
	function mintedSupply(address) external returns (uint256);
	function burnedSupply(address) external returns (uint256);

	function shouldMint(address mint) external returns (bool);
	function requestMint(address to) external;
	function shouldBurn(address mint) external returns (bool);
	function requestBurn(address from) external;
	function reportCollateral(uint256 amount) external;
}
