import React, { useState } from 'react';
import { Contract, parseUnits } from 'ethers';
import { FACTORY_ADDRESS, AMM_ABI, FACTORY_ABI, parseError } from '../utils/web3';

function RemoveLiquidity({ provider, account }) {
    const [tokenA, setTokenA] = useState('');
    const [tokenB, setTokenB] = useState('');
    const [sharesToRemove, setSharesToRemove] = useState('');
    const [loading, setLoading] = useState(false);
    const [status, setStatus] = useState('');
    const [balanceStr, setBalanceStr] = useState('');

    const fetchBalance = async () => {
        try {
            const signer = await provider.getSigner();
            const factory = new Contract(FACTORY_ADDRESS, FACTORY_ABI, signer);
            const poolAddr = await factory.getPool(tokenA, tokenB);

            if (poolAddr === "0x0000000000000000000000000000000000000000") return;

            const amm = new Contract(poolAddr, AMM_ABI, signer);
            const bal = await amm.balanceOf(account);
            // Assuming 18 decimals for LP tokens as per ERC20 standard constructor
            setBalanceStr((Number(bal) / 1e18).toFixed(4) + " LP");
        } catch (err) {
            console.log("Could not load balance");
        }
    };

    const handleRemove = async () => {
        if (!tokenA || !tokenB || !sharesToRemove) return;
        setStatus("Isolating Liquidity Sectors...");
        setLoading(true);

        try {
            const signer = await provider.getSigner();
            const factory = new Contract(FACTORY_ADDRESS, FACTORY_ABI, signer);

            const poolAddr = await factory.getPool(tokenA, tokenB);
            if (poolAddr === "0x0000000000000000000000000000000000000000") {
                throw new Error("Pool intercept failed: Not found");
            }

            const amm = new Contract(poolAddr, AMM_ABI, signer);
            const parsedShares = parseUnits(sharesToRemove, 18); // LP tokens are 18 dec

            setStatus("Executing Burn Protocol (removeLiquidity)...");
            const tx = await amm.removeLiquidity(parsedShares, account);
            await tx.wait();

            setStatus("Extraction Complete. Assets returned to local wallet.");
            fetchBalance();
        } catch (err) {
            console.error(err);
            setStatus("ERROR: " + parseError(err));
        }
        setLoading(false);
    };

    return (
        <div className="cyber-card">
            <h2 className="glitch-text">Extract Liquidity</h2>

            <label>Pair Vector A</label>
            <input className="cyber-input" placeholder="0x..." onChange={e => setTokenA(e.target.value)} onBlur={fetchBalance} />

            <label>Pair Vector B</label>
            <input className="cyber-input" placeholder="0x..." onChange={e => setTokenB(e.target.value)} onBlur={fetchBalance} />

            {balanceStr && <p style={{ color: 'var(--accent-secondary)' }}>Detected Matrix Share: {balanceStr}</p>}

            <label>Volume to Burn (LP Tokens)</label>
            <input className="cyber-input" type="number" placeholder="10.0" onChange={e => setSharesToRemove(e.target.value)} />

            <button className="cyber-button" onClick={handleRemove} disabled={loading}>
                {loading ? "Processing..." : "Extract Protocol"}
            </button>

            {status && <p style={{ marginTop: '20px', color: status.includes("ERROR") ? 'var(--warning)' : 'var(--text-color)' }}>
                &gt;_ {status}
            </p>}
        </div>
    );
}

export default RemoveLiquidity;
