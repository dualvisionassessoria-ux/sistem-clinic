import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import './index.css'
import App from './App.jsx'
import { ProvedorSessao } from './lib/sessao.jsx'
import { ProvedorAvisos } from './components/ui.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <BrowserRouter>
      <ProvedorAvisos>
        <ProvedorSessao>
          <App />
        </ProvedorSessao>
      </ProvedorAvisos>
    </BrowserRouter>
  </StrictMode>,
)
