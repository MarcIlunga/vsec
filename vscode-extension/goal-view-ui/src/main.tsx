import React from 'react'
import ReactDOM from 'react-dom/client'
import './goal-view.css'
import GoalPanel from './components/GoalPanel'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <GoalPanel />
  </React.StrictMode>,
)