import { invoke } from "@tauri-apps/api/core";

import { codeLineAt, codeLinesOf } from "./codelines";
import { followLink } from "./history";
import { isModifiedClick } from "./keys";
import { handleLink } from "./links";
import type { Block } from "./sourcepos";
import { body, view } from "./view";

function blockAt(target: Element): Block | null {
  // クリックされた要素に最も近い祖先で、位置表に含まれるもの
  for (let element: Element | null = target; element !== null; element = element.parentElement) {
    const found = view.table.find((block) => block.element === element);
    if (found !== undefined) {
      return found;
    }
  }
  return null;
}

/** 見つからないときは、縦方向で最も近いブロックを使う */
function nearestBlock(clientY: number): Block | null {
  let best: Block | null = null;
  let bestDistance = Number.POSITIVE_INFINITY;
  for (const block of view.table) {
    const rect = block.element.getBoundingClientRect();
    const distance =
      clientY < rect.top ? rect.top - clientY : clientY > rect.bottom ? clientY - rect.bottom : 0;
    if (distance < bestDistance) {
      best = block;
      bestDistance = distance;
    }
  }
  return best;
}

/** クリックした位置のブロック（コードブロックの中なら、その行）へのジャンプをNeovimに求める */
function requestJump(event: MouseEvent): void {
  // 描画を待っている間は無視する
  if (view.rendering) {
    return;
  }
  const target = event.target instanceof Element ? event.target : null;
  const block = (target !== null ? blockAt(target) : null) ?? nearestBlock(event.clientY);
  if (block === null) {
    return;
  }
  // コードブロックの中なら、クリックした位置のコードの行へ（囲いや余白の上なら、ブロックの開始行へ）
  const lines = codeLinesOf(block);
  const codeLine = lines !== null && target !== null && lines.pre.contains(target) ? codeLineAt(lines, event.clientY) : null;
  // スタンドアローンモードでは Neovim につながっていないので、失敗は捨てる
  invoke("jump", { gen: view.gen, version: view.version, line: codeLine ?? block.startLine }).catch(() => {});
}

/** ダブルクリックでジャンプさせない場所（1回のクリックに自分の動作があるもの） */
const OWN_CLICK = "a, summary, .mdsight-copy";

/**
 * 本文のクリックを、リンクの処理と、Neovimへのジャンプに振り分ける。
 * ジャンプするのは、修飾クリックと、修飾キーなしのダブルクリック。
 */
export function initClicks(): void {
  body.addEventListener("click", (event) => {
    if (!isModifiedClick(event)) {
      handleLink(event, (href) => void followLink(href));
      return;
    }
    // 修飾クリックのときは、リンクの通常動作を止める
    event.preventDefault();
    requestJump(event);
  });
  body.addEventListener("dblclick", (event) => {
    // 修飾クリックは、1回ずつのクリックでジャンプ済み
    if (isModifiedClick(event)) {
      return;
    }
    if (event.target instanceof Element && event.target.closest(OWN_CLICK) !== null) {
      return;
    }
    requestJump(event);
  });
}
