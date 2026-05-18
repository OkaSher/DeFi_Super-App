import { useState } from 'react'
import { connectWallet } from './utils/web3'
import Swap from './components/Swap'
import AddLiquidity from './components/AddLiquidity'
import RemoveLiquidity from './components/RemoveLiquidity'
import DAO from './components/DAO'

function App() {
    const [tab, setTab] = useState('SWAP');
    const [account, setAccount] = useState(null);
    const [provider, setProvider] = useState(null);

    const handleConnect = async () => {
        try {
            const { provider: p, account: a } = await connectWallet();
            setProvider(p);
            setAccount(a);
        } catch (e) {
            alert(e.message);
        }
    };

    return (
        <div className="crtscreen" style={{ minHeight: '100vh', padding: '50px' }}>
            <h1>DeFi Super-App <span style={{ color: 'var(--accent-primary)' }}>[AMM]</span></h1>

            <div style={{ marginBottom: '30px' }}>
                {account ? (
                    <p style={{ color: 'var(--accent-secondary)' }}>&gt; ROOT ACCESS GRANTED: {account.slice(0, 6)}...{account.slice(-4)}</p>
                ) : (
                    <button className="cyber-button" onClick={handleConnect}>Connect Interface</button>
                )}
            </div>

            {account && (
                <>
                    <div className="cyber-nav">
                        <span className={`nav-item ${tab === 'SWAP' ? 'active' : ''}`} onClick={() => setTab('SWAP')}>/ SWAP_PROTOCOL</span>
                        <span className={`nav-item ${tab === 'ADD' ? 'active' : ''}`} onClick={() => setTab('ADD')}>/ INJECT_LIQUIDITY</span>
                        <span className={`nav-item ${tab === 'REMOVE' ? 'active' : ''}`} onClick={() => setTab('REMOVE')}>/ EXTRACT_LIQUIDITY</span>
                        <span className={`nav-item ${tab === 'DAO' ? 'active' : ''}`} onClick={() => setTab('DAO')}>/ DAO_PORTAL</span>
                    </div>

                    <div style={{ maxWidth: '600px' }}>
                        {tab === 'SWAP' && <Swap provider={provider} account={account} />}
                        {tab === 'ADD' && <AddLiquidity provider={provider} account={account} />}
                        {tab === 'REMOVE' && <RemoveLiquidity provider={provider} account={account} />}
                        {tab === 'DAO' && <DAO provider={provider} account={account} />}
                    </div>
                </>
            )}
        </div>
    )
}

export default App

