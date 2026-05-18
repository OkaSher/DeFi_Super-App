import React, { useState } from 'react';
import { Contract, parseUnits } from 'ethers';
import { FACTORY_ADDRESS, AMM_ABI, ERC20_ABI, FACTORY_ABI, parseError } from '../utils/web3';

function AddLiquidity({ provider, account }) {
    const [tokenA, setTokenA] = useState('');
    const [tokenB, setTokenB] = useState('');
    const [amountA, setAmountA] = useState('');
    const [amountB, setAmountB] = useState('');
    const [loading, setLoading] = useState(false);
    const [status, setStatus] = useState('');

    const fetchRatios = async () => {
        // In a production app, we would fetch getReserves() to calculate optimal amounts
        // Based on the Y*X=K formula. For brevity in this assignment, we rely on the AMM's internal
        // logic which automatically scales amountB if the pool already exists.
    };

    const handleAdd = async () => {
        if (!tokenA || !tokenB || !amountA || !amountB) return;
        setStatus("Establishing connection to Liquidity Node...");
        setLoading(true);

        try {
            const signer = await provider.getSigner();
            const factory = new Contract(FACTORY_ADDRESS, FACTORY_ABI, signer);

            let poolAddr = await factory.getPool(tokenA, tokenB);
            if (poolAddr === "0x0000000000000000000000000000000000000000") {
                setStatus("Pool not found. Triggering Factory Synthesis (createPool)...");
                const txCreate = await factory.createPool(tokenA, tokenB);
                await txCreate.wait();
                poolAddr = await factory.getPool(tokenA, tokenB);
            }

            const tA = new Contract(tokenA, ERC20_ABI, signer);
            const tB = new Contract(tokenB, ERC20_ABI, signer);
            const decA = await tA.decimals();
            const decB = await tB.decimals();

            const parsedA = parseUnits(amountA, decA);
            const parsedB = parseUnits(amountB, decB);

            setStatus("Approving asset streams...");
            await (await tA.approve(poolAddr, parsedA)).wait();
            await (await tB.approve(poolAddr, parsedB)).wait();

            setStatus("Injecting Liquidity Base...");
            const amm = new Contract(poolAddr, AMM_ABI, signer);

            // Must pass token0 to amount0Desired, requiring local sorting check:
            const isToken0A = tokenA.toLowerCase() < tokenB.toLowerCase();
            const amount0 = isToken0A ? parsedA : parsedB;
            const amount1 = isToken0A ? parsedB : parsedA;

            const txMint = await amm.addLiquidity(amount0, amount1, account);
            await txMint.wait();

            setStatus("Injection Complete. Tokens locked in matrix.");
        } catch (err) {
            console.error(err);
            setStatus("ERROR: " + parseError(err));
        }
        setLoading(false);
    };

    return (
        <div className="cyber-card">
            <h2 className="glitch-text">Inject Liquidity</h2>

            <label>Asset Core A (Address)</label>
            <input className="cyber-input" placeholder="0x..." onChange={e => setTokenA(e.target.value)} />
            <input className="cyber-input" type="number" placeholder="Volume A" onChange={e => setAmountA(e.target.value)} />

            <label>Asset Core B (Address)</label>
            <input className="cyber-input" placeholder="0x..." onChange={e => setTokenB(e.target.value)} />
            <input className="cyber-input" type="number" placeholder="Volume B" onChange={e => setAmountB(e.target.value)} />

            <button className="cyber-button" onClick={handleAdd} disabled={loading}>
                {loading ? "Processing..." : "Inject Matrix"}
            </button>

            {status && <p style={{ marginTop: '20px', color: status.includes("ERROR") ? 'var(--warning)' : 'var(--text-color)' }}>
                &gt;_ {status}
            </p>}
        </div>
    );
}

export default AddLiquidity;
