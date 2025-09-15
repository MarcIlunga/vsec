import React, { FunctionComponent, useEffect, useState } from 'react';
import styles from './Accordion.module.css';
import MinimalButton from './MinimalButton';
import { VscChevronDown, VscEye, VscEyeClosed } from 'react-icons/vsc';

type AccordionProps = {
  collapsed: boolean;
  title: string;
  collapseHandler?: (params: any) => void;
  secondaryActionHandler?: (params: any) => void;
  secondaryActionIcon?: 'eye' | 'eye-closed';
  children: React.ReactNode;
};

const Accordion: FunctionComponent<AccordionProps> = (props) => {
  const { title, collapseHandler, secondaryActionHandler, secondaryActionIcon } = props;
  const [collapsed, setCollapsed] = useState(props.collapsed);
  
  useEffect(() => {
    setCollapsed(props.collapsed);
  }, [props.collapsed]);

  const panelClasses = [styles.panel];
  if (collapsed) {
    panelClasses.push(styles.closed);
  }

  const toggleCollapse = collapseHandler ? collapseHandler : () => setCollapsed(!collapsed);

  const getSecondaryActionIcon = () => {
    if (secondaryActionIcon === 'eye') return <VscEye />;
    if (secondaryActionIcon === 'eye-closed') return <VscEyeClosed />;
    return null;
  };

  const secondaryActionButton = (secondaryActionHandler !== undefined && secondaryActionIcon !== undefined) ? (
    <MinimalButton onClick={secondaryActionHandler} className={styles.deemphasize}>
      {getSecondaryActionIcon()}
    </MinimalButton>
  ) : null;
  
  const secondaryAction = collapsed ? null : secondaryActionButton;
  
  const actionRow = (
    <div>
      {secondaryAction}
      <MinimalButton 
        ariaLabel="Collapse" 
        onClick={toggleCollapse}
        className={styles.accordionButton}
      >
        <VscChevronDown 
          className={`${styles.chevronIcon} ${!collapsed ? styles.rotated : ''}`}
        />
      </MinimalButton>
    </div>
  );

  return (
    <div className={styles.block}>
      {/* The header with title and button */}
      <div className={styles.header}>
        <span className={!collapsed ? styles.deemphasize : ''}>{title}</span>
        {actionRow}
      </div>

      {/* The panel that collapses */}
      <div className={panelClasses.join(' ')}>
        {props.children}
      </div>
    </div>
  );
};

export default Accordion;
