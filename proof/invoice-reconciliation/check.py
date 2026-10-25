from decimal import Decimal, ROUND_HALF_UP
import json
from pathlib import Path

MONEY = Decimal('0.01')

def audit(invoice):
    issues = []
    calculated = Decimal('0')
    for index, item in enumerate(invoice['items'], 1):
        missing = [key for key in ('description','quantity','unit_price','tax_pct','line_total') if item.get(key) in (None, '')]
        if missing:
            issues.append({'line':index,'kind':'missing','fields':missing})
            continue
        try:
            quantity = Decimal(str(item['quantity']))
            price = Decimal(str(item['unit_price']))
            tax = Decimal(str(item['tax_pct']))
            observed = Decimal(str(item['line_total']))
            expected = (quantity * price * (1 + tax / 100)).quantize(MONEY, rounding=ROUND_HALF_UP)
        except Exception:
            issues.append({'line':index,'kind':'invalid_number'})
            continue
        calculated += observed
        if expected != observed:
            issues.append({'line':index,'kind':'line_mismatch','expected':str(expected),'observed':str(observed)})
    if invoice.get('total') is None:
        issues.append({'kind':'missing_header_total'})
    elif calculated != Decimal(str(invoice['total'])):
        issues.append({'kind':'invoice_mismatch','calculated':str(calculated),'observed':str(invoice['total'])})
    return {'number':invoice['number'],'currency':invoice['currency'],'items_preserved':len(invoice['items']),'issues':issues}

if __name__ == '__main__':
    from copy import deepcopy
    sample = {'number':'DEMO-001','date':'2026-10-25','supplier':'Synthetic Example Ltd','currency':'EUR','total':'49.88','items':[
        {'description':'Test item, line one\ncontinued description','quantity':'2','unit_price':'19.95','tax_pct':'19','line_total':'47.48'},
        {'description':'Second test item','quantity':'1','unit_price':'2.40','tax_pct':'0','line_total':'2.40'}]}
    valid = audit(sample)
    assert valid['issues'] == [] and valid['items_preserved'] == 2
    missing = deepcopy(sample); missing['items'][0]['quantity'] = None
    missing = audit(missing)
    assert any(x.get('kind') == 'missing' and 'quantity' in x['fields'] for x in missing['issues'])
    mismatch = deepcopy(sample); mismatch['total'] = '49.89'
    mismatch = audit(mismatch)
    assert any(x.get('kind') == 'invoice_mismatch' for x in mismatch['issues'])
    result = {'scope':'Synthetic invoice reconciliation only. No client PDFs parsed, Excel workbook or supplier layout tested. Tax rounding is a stated sample convention, not a universal accounting rule.', 'cases_passed':3,'cases_total':3,'cases':[valid,missing,mismatch]}
    Path(__file__).with_name('results.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print('3/3 synthetic reconciliation checks passed')
