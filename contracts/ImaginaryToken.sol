// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ImaginaryToken is Ownable, ERC20 {
	using SafeMath for uint256;
	
	constructor(
		string memory name,
		string memory symbol,

		address owner
	) ERC20(name, symbol) {
		_mint(owner, uint256(420).mul(1000).mul(10**decimals()));
		transferOwnership(owner);
	}

}
