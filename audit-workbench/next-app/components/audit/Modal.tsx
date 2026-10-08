"use client";
import { useEffect, useRef } from "react";
export default function Modal({
  title,
  onClose,
  children,
  error,
  busy = false,
}: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
  error?: string;
  busy?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const node = ref.current;
    node?.showModal();
    return () => node?.close();
  }, []);
  return (
    <dialog
      ref={ref}
      className="modal"
      aria-label={title}
      onCancel={(e) => {
        e.preventDefault();
        if (!busy) onClose();
      }}
    >
      <header className="modal-heading">
        <h2>{title}</h2>
        <button
          type="button"
          onClick={onClose}
          disabled={busy}
          aria-label="关闭"
        >
          ×
        </button>
      </header>
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      {children}
    </dialog>
  );
}
