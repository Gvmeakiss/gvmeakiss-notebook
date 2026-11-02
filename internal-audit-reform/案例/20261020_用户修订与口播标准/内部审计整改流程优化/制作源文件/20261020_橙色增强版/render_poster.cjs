const fs = require('fs');
const path = require('path');
const {pathToFileURL} = require('url');

const {chromium} = require(process.env.PLAYWRIGHT_MODULE || '/Users/aatrox/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const chromePath = process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const projectRoot = path.resolve(__dirname, '../..');
const workspace = path.resolve(projectRoot, '..');
const delivery = path.join(projectRoot, '最终交付/20261020_橙色增强版');
const checks = path.join(workspace, '归档/20261020_海报橙色增强核对');
const baselineFile = path.resolve(__dirname, '../20261020_视觉丰富版/poster.html');
const output = path.join(delivery, '内部审计整改流程优化与操作详解_宣导海报.png');

(async () => {
  fs.mkdirSync(delivery, {recursive: true});
  fs.mkdirSync(checks, {recursive: true});
  const browser = await chromium.launch({executablePath: chromePath, headless: true});
  try {
    const page = await browser.newPage({viewport: {width: 1440, height: 1200}, deviceScaleFactor: 2});
    const external = [];
    await page.route('**/*', request => {
      if (/^https?:/.test(request.request().url())) {
        external.push(request.request().url());
        return request.abort();
      }
      return request.continue();
    });
    await page.goto(pathToFileURL(path.join(__dirname, 'poster.html')).href);
    await page.evaluate(() => document.fonts.ready);
    const qa = await page.evaluate(() => {
      const root = document.querySelector('#poster').getBoundingClientRect();
      const boxes = [], outside = [], overflow = [];
      const selector = 'h1,h2,h3,p,.brand-name,.year,.number';
      for (const element of document.querySelectorAll(selector)) {
        const b = element.getBoundingClientRect();
        const section = element.closest('section').getBoundingClientRect();
        const item = {text: element.innerText, x: b.x, y: b.y, width: b.width, height: b.height};
        boxes.push(item);
        if (b.left < root.left || b.right > root.right || b.top < section.top || b.bottom > section.bottom) outside.push(item);
        if (element.scrollWidth > element.clientWidth + 1 || element.scrollHeight > element.clientHeight + 1) overflow.push(item);
      }
      const collisions = [];
      for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
        const a = boxes[i], b = boxes[j];
        if (a.x < b.x+b.width-1 && a.x+a.width > b.x+1 && a.y < b.y+b.height-1 && a.y+a.height > b.y+1) collisions.push([a.text, b.text]);
      }
      return {
        width: root.width, height: root.height,
        title: document.querySelector('h1').innerText,
        goals: Array.from(document.querySelectorAll('.goal h3'), e => e.innerText),
        stages: Array.from(document.querySelectorAll('.flow-item h3'), e => e.innerText),
        icons: Array.from(document.querySelectorAll('.step-icon'), element => {
          const box = element.getBoundingClientRect();
          return {step: element.closest('.flow-item').dataset.step, width: box.width, height: box.height};
        }),
        text: document.querySelector('#poster').innerText,
        outside, overflow, collisions, boxes,
      };
    });
    const baselinePage = await browser.newPage({viewport: {width: 1440, height: 1200}});
    await baselinePage.goto(pathToFileURL(baselineFile).href);
    const baselineText = await baselinePage.locator('#poster').innerText();
    await baselinePage.close();
    const normalize = text => text.replace(/\s+/g, '');
    const contentUnchanged = normalize(qa.text) === normalize(baselineText);
    const expectedTitle = '内部审计整改流程优化与操作详解';
    const expectedStages = ['任务下发','成因分析','措施制定','过程追踪','验收质检','业审联动','考核落地'];
    const passed = contentUnchanged && qa.title === expectedTitle
      && JSON.stringify(qa.goals) === JSON.stringify(['深化整改','流程优化','标准统一'])
      && JSON.stringify(qa.stages) === JSON.stringify(expectedStages)
      && qa.icons.length === 7 && qa.icons.every(icon => icon.width === 62 && icon.height === 62)
      && !/宣贯|整改革新|七步法|五维分析工具|五位分析工具|新机制|直抵问题本质/.test(qa.text)
      && !/。|总部涉及整改的部门/.test(qa.text)
      && normalize(qa.text).includes('稽核发现问题：年度专项稽核、常规稽核项目发现的问题；三函涉及事项：指令函、警示函、知询函涉及的整改事项')
      && qa.text.includes('具体要求详见配套PPT及宣导视频')
      && !qa.outside.length && !qa.overflow.length && !qa.collisions.length && !external.length;
    fs.writeFileSync(path.join(checks, 'layout-check.json'), JSON.stringify({passed, contentUnchanged, baselineFile, external, ...qa}, null, 2));
    if (!passed) throw new Error('Content or layout validation failed. See layout-check.json.');
    await page.locator('#poster').screenshot({path: output});
    await page.locator('.page-one').screenshot({path: path.join(checks, '第一版面.png')});
    await page.locator('.page-two').screenshot({path: path.join(checks, '第二版面.png')});
    console.log(JSON.stringify({passed, output, width: qa.width*2, height: qa.height*2, title: qa.title, goals: qa.goals, stages: qa.stages}, null, 2));
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
