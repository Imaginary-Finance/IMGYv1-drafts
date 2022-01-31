// contracts/imaginaryMint.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface Oracle {
	function latestRoundData() external view returns (
		uint80 roundId,
		int256 answer,
		uint256 startedAt,
		uint256 updatedAt, 
		uint80 answeredInRound
	);
}

interface LPToken {
	function latestRoundData() external view returns (
		uint80 roundId,
		int256 answer,
		uint256 startedAt,
		uint256 updatedAt, 
		uint80 answeredInRound
	);

    function token0() external view returns(address);
    function token1() external view returns(address);
}

abstract contract LPOracle {
	using SafeMath for uint256;
    using SafeERC20 for IERC20;

	address public LPtoken;			//underlying price

    address public asset0;
    address public asset0Oracle;
    address public asset1;
    address public asset1Oracle;

    function _setAssetOracles(
        address lpToken,
        address oracle0,
        address oracle1
    ) internal {
        LPtoken = lpToken;
        asset0 = LPToken(lpToken).token0();
        asset0Oracle = oracle0;
        asset1 = LPToken(lpToken).token1();
        asset1Oracle = oracle1;
    }

    function assetPrice() public view returns(uint256) {
        uint256 totalValue = 0;
        (,int256 price0,,,) = Oracle(asset0Oracle).latestRoundData();
        uint256 value0 = IERC20(asset0).balanceOf(LPtoken).mul(uint256(price0));
        (,int256 price1,,,) = Oracle(asset1Oracle).latestRoundData();
        uint256 value1 = IERC20(asset1).balanceOf(LPtoken).mul(uint256(price1));
        totalValue = value0.add(value1);
        return(totalValue);
	}

}