// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Mydex.sol";
import "../src/Rnt.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";


contract MyDexTest is Test {
    ///  DEX相关合约实例
    MyDex public dex;                      
    RNT public token;                      
    IUniswapV2Factory public factory;      
    IUniswapV2Router02 public router;     
    IUniswapV2Pair public pair;           
    IWETH public weth;                    
    
    /// dev测试配置常量
    address public user;                   // 测试用户地址
    uint256 constant INITIAL_ETH_LIQUIDITY = 100 ether;
    uint256 constant INITIAL_TOKEN_LIQUIDITY = 1000000 * 10**18;
    

    function setUp() public {

        // 部署基础设施
        user = makeAddr("user");
        factory = IUniswapV2Factory(deployCode(
            "out/UniswapV2Factory.sol/UniswapV2Factory.json",
            abi.encode(address(this))
        ));


        // 部署合约
        weth = IWETH(deployCode("out/WETH9.sol/WETH9.json"));
        
        router = IUniswapV2Router02(deployCode(
            "out/UniswapV2Router02.sol/UniswapV2Router02.json",
            abi.encode(address(factory), address(weth))
        ));
       
        // 部署和初始化业务合约
        dex = new MyDex(address(factory), address(router));
        
        token = new RNT();

        // 设置测试账户初始状态
        vm.deal(user, 1000 ether);
        token.transfer(user, INITIAL_TOKEN_LIQUIDITY);

        // 创建交易对
        address pairAddress = factory.createPair(address(token), address(weth));
        pair = IUniswapV2Pair(pairAddress);
    }
    

    function testAddLiquidity() public {
        vm.startPrank(user);
        

        // 设置
        token.approve(address(router), type(uint256).max);
        uint amountTokenDesired = 900 ether;
        uint amountETH = 1 ether;

        // 执行
        router.addLiquidityETH{value: amountETH}(
            address(token),
            amountTokenDesired,
            amountTokenDesired * 99 / 100,  // 最小代币数量（1% 滑点）
            amountETH * 99 / 100,          // 最小 ETH 数量（1% 滑点）
            user,
            block.timestamp          // 2分钟过期时间
        ); 



        require(pair.balanceOf(user) > 0, "No LP tokens received");
        vm.stopPrank();
    }


    function testSwapExactETHForTokens() public {
        vm.startPrank(user);
        
        // 准备：添加初始流动性
        _addInitialLiquidity();

        // 记录初始状态
        uint256 userInitialETH = user.balance;
        uint256 userInitialToken = token.balanceOf(user);
        
        // 执行交换
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token);

        router.swapExactETHForTokens{value: 1 ether}(
            0,  // 最小获得代币数量
            path,
            user,
            block.timestamp
        );

        // 验证结果
        assertGt(token.balanceOf(user), userInitialToken, "Token balance should increase");
        assertLt(user.balance, userInitialETH, "ETH balance should decrease");
        vm.stopPrank();
    }


    function testSwapExactTokensForETH() public {
        vm.startPrank(user);
        
        // 先添加流动性
        token.approve(address(router), type(uint256).max);
        router.addLiquidityETH{value: 10 ether}(
            address(token),
            9000 ether,
            8900 ether,
            9.9 ether,
            user,
            block.timestamp
        );

        // 记录交换前的余额
        uint256 userInitialETH = user.balance;
        uint256 userInitialToken = token.balanceOf(user);
        uint256 swapAmount = 100 ether;

        // 设置交换路径：Token -> WETH
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(weth);

        // 执行交换
        token.approve(address(router), swapAmount);
        router.swapExactTokensForETH(
            swapAmount,
            0,  // 接受任何数量的 ETH 输出
            path,
            user,
            block.timestamp
        );

        // 验证余额变化
        assertLt(token.balanceOf(user), userInitialToken, "Token balance should decrease");
        assertGt(user.balance, userInitialETH, "ETH balance should increase");
        vm.stopPrank();
    }


    function testRemoveLiquidity() public {
        vm.startPrank(user);
        
        // 先添加流动性
        token.approve(address(router), type(uint256).max);
        (,, uint256 liquidity) = router.addLiquidityETH{value: 10 ether}(
            address(token),
            9000 ether,
            8900 ether,
            9.9 ether,
            user,
            block.timestamp
        );

        // 记录初始状态
        uint256 userInitialETH = user.balance;
        uint256 userInitialToken = token.balanceOf(user);

        // 移除流动性
        pair.approve(address(router), liquidity);
        router.removeLiquidityETH(
            address(token),
            liquidity ,
            0,  // 接受任何数量的代币
            0,  // 接受任何数量的 ETH
            user,
            block.timestamp
        );

        // 验证余额变化
        assertGt(token.balanceOf(user), userInitialToken, "Token balance should increase");
        assertGt(user.balance, userInitialETH, "ETH balance should increase");
        assertEq(pair.balanceOf(user), 0, "Should have  LP tokens 0");
        vm.stopPrank();
    }


    function testGetAmountsOut() public {
        vm.startPrank(user);
        
        // 先添加流动性
        token.approve(address(router), type(uint256).max);
        router.addLiquidityETH{value: 10 ether}(
            address(token),
            9000 ether,
            8900 ether,
            9.9 ether,
            user,
            block.timestamp
        );

        // 设置查询路径
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token);

        // 获取并验证输出金额
        uint256[] memory amounts = router.getAmountsOut(1 ether, path);
        assertEq(amounts.length, 2, "Should return amounts for both tokens");
        assertGt(amounts[1], 0, "Output amount should be greater than 0");
        vm.stopPrank();
    }



    function _addInitialLiquidity() internal returns (uint256 liquidity) {
        token.approve(address(router), type(uint256).max);
        (,, liquidity) = router.addLiquidityETH{value: 10 ether}(
            address(token),
            9000 ether,
            8900 ether,
            9.9 ether,
            user,
            block.timestamp
        );
    }

    /// @dev 允许合约接收 ETH
    receive() external payable {}
}
