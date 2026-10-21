import json

with open('assets/default_plans.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

print(f"Total plans: {len(data)}")

dates_count = {}
for p in data:
    dept = p.get('departmentName', 'Unknown')
    time_val = p.get('executionTime', '')
    if any(char.isdigit() for char in time_val) or '/' in time_val or '-' in time_val or 'እስከ' in time_val:
        dates_count[dept] = dates_count.get(dept, 0) + 1

with open('dept_dates_summary.json', 'w', encoding='utf-8') as out:
    json.dump({
        'total': len(data),
        'dates_by_dept': dates_count,
        'samples': [
            {'dept': p.get('departmentName'), 'task': p.get('mainTask'), 'time': p.get('executionTime')}
            for p in data if any(char.isdigit() for char in p.get('executionTime', ''))
        ][:15]
    }, out, ensure_ascii=False, indent=2)

print("Saved to dept_dates_summary.json")
