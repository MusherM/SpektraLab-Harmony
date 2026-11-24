export class ExportAttempt {
  nativeOperation: number = 0;
  cancelled: boolean = false;
  committing: boolean = false;
  private confirmation?: Promise<void>;
  private resume?: () => void;

  requestConfirmation(): boolean {
    if (this.cancelled || this.committing || this.confirmation) return false;
    this.confirmation = new Promise<void>((resolve) => { this.resume = resolve; });
    return true;
  }

  resolveConfirmation(cancel: boolean): void {
    if (cancel) this.cancelled = true;
    const resume = this.resume;
    this.confirmation = undefined;
    this.resume = undefined;
    resume?.();
  }

  async beginCommit(): Promise<boolean> {
    while (this.confirmation) await this.confirmation;
    if (this.cancelled) return false;
    this.committing = true;
    return true;
  }
}
