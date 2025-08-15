import { TreeDataProvider, TreeItem, TreeItemCollapsibleState, ProviderResult, Event, EventEmitter, ThemeIcon } from 'vscode';

type NodeKind = 'status' | 'group' | 'action';

type BaseNode = {
  readonly id: string;
  readonly kind: NodeKind;
  readonly label: string;
};

type GroupNode = BaseNode & {
  readonly kind: 'group';
  readonly children: LeafNode[];
};

type StatusNode = BaseNode & { readonly kind: 'status'; readonly description?: string };

type LeafNode = BaseNode & { readonly kind: 'action'; readonly command: string; readonly args?: any[]; readonly icon?: ThemeIcon };

export class ActionsViewProvider implements TreeDataProvider<BaseNode> {
  public static readonly viewId = 'vsec.actions';
  private _onDidChangeTreeData: EventEmitter<BaseNode | undefined | void> = new EventEmitter<BaseNode | undefined | void>();
  readonly onDidChangeTreeData: Event<BaseNode | undefined | void> = this._onDidChangeTreeData.event;

  // Simple status cache updated from proofView notifications
  private lastGoalCount: number | undefined = undefined;
  private lastStatusText: string = 'Idle';

  refresh(): void { this._onDidChangeTreeData.fire(); }

  updateStatus(proofView: any): void {
    try {
      const goals = proofView?.proofState?.goals ?? [];
      const msgs = Array.isArray(proofView?.messages) ? proofView.messages.length : 0;
      if (Array.isArray(goals)) {
        this.lastGoalCount = goals.length;
        this.lastStatusText = this.lastGoalCount > 0 ? `${this.lastGoalCount} goal(s)` : (msgs > 0 ? `No goals (messages: ${msgs})` : 'No goals');
      } else {
        this.lastStatusText = 'Not in proof mode';
        this.lastGoalCount = undefined;
      }
    } catch {
      this.lastStatusText = 'Unknown';
      this.lastGoalCount = undefined;
    }
    this.refresh();
  }

  getTreeItem(element: BaseNode): TreeItem | Thenable<TreeItem> {
    if (element.kind === 'group') {
      const item = new TreeItem(element.label, TreeItemCollapsibleState.Expanded);
      return item;
    }
    if (element.kind === 'status') {
      const item = new TreeItem(element.label, TreeItemCollapsibleState.None);
      item.iconPath = new ThemeIcon(this.lastGoalCount && this.lastGoalCount > 0 ? 'flame' : 'verified');
      item.description = (element as StatusNode).description;
      item.tooltip = `Proof status: ${item.description ?? ''}`;
      // Not clickable
      return item;
    }
    const leaf = element as LeafNode;
    const item = new TreeItem(leaf.label, TreeItemCollapsibleState.None);
    item.command = { command: leaf.command, title: leaf.label, arguments: leaf.args };
    if (leaf.icon) item.iconPath = leaf.icon;
    return item;
  }

  getChildren(element?: BaseNode): ProviderResult<BaseNode[]> {
    if (!element) {
      const status: StatusNode = {
        id: 'status',
        kind: 'status',
        label: 'Status',
        description: this.lastStatusText,
      };
      // All actions are exposed here (no status bar buttons)
      const actions: LeafNode[] = [
        { id: 'showGoals', kind: 'action', label: 'Show Goals', command: 'vsec.runShowGoalPanel', icon: new ThemeIcon('target') },
        { id: 'stepForward', kind: 'action', label: 'Step Forward', command: 'vsec.stepForward', icon: new ThemeIcon('arrow-right') },
        { id: 'stepBackward', kind: 'action', label: 'Step Backward', command: 'vsec.stepBackward', icon: new ThemeIcon('arrow-left') },
        { id: 'interpretToPoint', kind: 'action', label: 'Interpret to Cursor', command: 'vsec.interpretToPoint', icon: new ThemeIcon('debug-step-into') },
        { id: 'interpretToEnd', kind: 'action', label: 'Interpret to End', command: 'vsec.interpretToEnd', icon: new ThemeIcon('debug-step-out') },
        { id: 'checkProof', kind: 'action', label: 'Check Proof', command: 'vsec.checkProof', icon: new ThemeIcon('check') },
        { id: 'revertPrev', kind: 'action', label: 'Revert to Previous Successful Step', command: 'vsec.revertToPrevious', icon: new ThemeIcon('history') },
        { id: 'killEasyCrypt', kind: 'action', label: 'Kill EasyCrypt Process', command: 'vsec.killEasyCrypt', icon: new ThemeIcon('trash') },
      ];
      return [status, ...actions];
    }
    if (element.kind === 'group') {
      return (element as GroupNode).children;
    }
    return [];
  }
}


