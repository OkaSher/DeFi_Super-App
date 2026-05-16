import React, { useState } from 'react';
import { Contract, parseUnits } from 'ethers';
import { FACTORY_ADDRESS, AMM_ABI, ERC20_ABI, FACTORY_ABI, parseError } from '../utils/web3';

function Swap({ provider, account }) {
    const [tokenIn, setTokenIn] = useState('');
    const [tokenOut, setTokenOut] = useState('');
    const [amountIn, setAmountIn] = useState('');
    const [loading, setLoading] = useState(false);
    const [status, setStatus] = useState('');

    const handleSwap = async () => {
        if (!tokenIn || !tokenOut || !amountIn) return;
        setStatus("Initiating hack...");
        setLoading(true);

        try {
            const signer = await provider.getSigner();
            const factory = new Contract(FACTORY_ADDRESS, FACTORY_ABI, signer);

            const poolAddr = await factory.getPool(tokenIn, tokenOut);
            if (poolAddr === "0x0000000000000000000000000000000000000000") {
                throw new Error("Pool intercept failed: Pair not found");
            }

            const tokenContract = new Contract(tokenIn, ERC20_ABI, signer);
            const dec = await tokenContract.decimals();
            const parsedAmount = parseUnits(amountIn, dec);

            setStatus("Bypassing firewall (Approving)...");
            const tx1 = await tokenContract.approve(poolAddr, parsedAmount);
            await tx1.wait();

            setStatus("Executing Swap Payload...");
            const amm = new Contract(poolAddr, AMM_ABI, signer);

            // We pass 0 for minAmountOut for demo purposes (dangerous in prod, OK for demo)
            const tx2 = await amm.swap(parsedAmount, 0, tokenIn, account);
            await tx2.wait();

            setStatus("Swap Payload Executed successfully.");
        } catch (err) {
            console.error(err);
            setStatus("ERROR: " + parseError(err));
        }
        setLoading(false);
    };

    return (
        <div className="cyber-card">
            <h2 className="glitch-text">Swap Protocol</h2>

            <label>Token IN Array (Address)</label>
            <input className="cyber-input" placeholder="0x..." onChange={e => setTokenIn(e.target.value)} />

            <label>Token OUT Array (Address)</label>
            <input className="cyber-input" placeholder="0x..." onChange={e => setTokenOut(e.target.value)} />

            <label>Volume (Amount)</label>
            <input className="cyber-input" type="number" placeholder="100.0" onChange={e => setAmountIn(e.target.value)} />

            <button className="cyber-button" onClick={handleSwap} disabled={loading}>
                {loading ? "Processing..." : "Execute Swap"}
            </button>

            {status && <p style={{ marginTop: '20px', color: status.includes("ERROR") ? 'var(--warning)' : 'var(--text-color)' }}>
                &gt;_ {status}
            </p>}
        </div>
    );
}

export default Swap;
