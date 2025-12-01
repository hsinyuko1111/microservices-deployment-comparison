#!/usr/bin/env python3
"""
compare_results.py - Compare Locust load test results between LocalStack and AWS

Usage:
    python analysis/compare_results.py
    
    # Or specify specific result directories:
    python analysis/compare_results.py --localstack analysis/results/localstack --aws analysis/results/aws
"""

import argparse
import os
import sys
from pathlib import Path
from datetime import datetime

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Configuration
RESULTS_DIR = Path("analysis/results")
LOCALSTACK_DIR = RESULTS_DIR / "localstack"
AWS_DIR = RESULTS_DIR / "aws"
OUTPUT_DIR = RESULTS_DIR / "comparison"


def find_latest_csv(directory: Path, pattern: str = "results_stats.csv") -> Path | None:
    """Find the stats CSV file in the directory."""
    csv_file = directory / pattern
    if csv_file.exists():
        return csv_file
    
    # Try to find in subdirectories
    for subdir in directory.iterdir():
        if subdir.is_dir():
            csv_file = subdir / pattern
            if csv_file.exists():
                return csv_file
    return None


def load_stats(csv_path: Path) -> pd.DataFrame | None:
    """Load Locust stats CSV file."""
    if not csv_path or not csv_path.exists():
        return None
    return pd.read_csv(csv_path)


def load_history(directory: Path) -> pd.DataFrame | None:
    """Load Locust stats history CSV file."""
    history_file = directory / "results_stats_history.csv"
    if not history_file.exists():
        # Try subdirectory
        for subdir in directory.iterdir():
            if subdir.is_dir():
                history_file = subdir / "results_stats_history.csv"
                if history_file.exists():
                    break
    
    if not history_file.exists():
        return None
    
    df = pd.read_csv(history_file)
    if 'Timestamp' in df.columns:
        df['Timestamp'] = pd.to_datetime(df['Timestamp'], unit='s')
    return df


def get_aggregated_row(df: pd.DataFrame) -> pd.Series:
    """Get the aggregated row from stats DataFrame."""
    if 'Name' in df.columns:
        agg_rows = df[df['Name'] == 'Aggregated']
        if len(agg_rows) > 0:
            return agg_rows.iloc[0]
    return df.iloc[-1]


def create_summary(localstack_stats: pd.DataFrame, aws_stats: pd.DataFrame) -> pd.DataFrame:
    """Create comparison summary table."""
    ls = get_aggregated_row(localstack_stats)
    aws = get_aggregated_row(aws_stats)
    
    def safe_get(row, key, default=0):
        return row.get(key, default) if key in row else default
    
    def calc_diff(ls_val, aws_val):
        if ls_val == 0:
            return "N/A"
        diff = ((aws_val - ls_val) / ls_val) * 100
        return f"{diff:+.1f}%"
    
    summary_data = {
        'Metric': [
            'Total Requests',
            'Failed Requests',
            'Failure Rate (%)',
            'Avg Response Time (ms)',
            'Median Response Time (ms)',
            'P95 Response Time (ms)',
            'P99 Response Time (ms)',
            'Requests/sec (RPS)',
        ],
        'LocalStack': [
            int(safe_get(ls, 'Request Count')),
            int(safe_get(ls, 'Failure Count')),
            round(safe_get(ls, 'Failure Count') / max(safe_get(ls, 'Request Count'), 1) * 100, 2),
            round(safe_get(ls, 'Average Response Time'), 2),
            round(safe_get(ls, 'Median Response Time'), 2),
            round(safe_get(ls, '95%'), 2),
            round(safe_get(ls, '99%'), 2),
            round(safe_get(ls, 'Requests/s'), 2),
        ],
        'AWS': [
            int(safe_get(aws, 'Request Count')),
            int(safe_get(aws, 'Failure Count')),
            round(safe_get(aws, 'Failure Count') / max(safe_get(aws, 'Request Count'), 1) * 100, 2),
            round(safe_get(aws, 'Average Response Time'), 2),
            round(safe_get(aws, 'Median Response Time'), 2),
            round(safe_get(aws, '95%'), 2),
            round(safe_get(aws, '99%'), 2),
            round(safe_get(aws, 'Requests/s'), 2),
        ],
    }
    
    summary = pd.DataFrame(summary_data)
    summary['Difference'] = [
        calc_diff(summary['LocalStack'][i], summary['AWS'][i]) 
        if isinstance(summary['LocalStack'][i], (int, float)) else "N/A"
        for i in range(len(summary))
    ]
    
    return summary


def plot_latency_comparison(ls_stats: pd.DataFrame, aws_stats: pd.DataFrame, output_dir: Path):
    """Create latency comparison bar chart."""
    fig, ax = plt.subplots(figsize=(12, 6))
    
    # Filter endpoints (exclude Aggregated)
    ls_endpoints = ls_stats[ls_stats['Name'] != 'Aggregated'].copy()
    aws_endpoints = aws_stats[aws_stats['Name'] != 'Aggregated'].copy()
    
    # Get common endpoints
    endpoints = ls_endpoints['Name'].unique()
    
    x = range(len(endpoints))
    width = 0.35
    
    ls_latencies = []
    aws_latencies = []
    
    for e in endpoints:
        ls_row = ls_endpoints[ls_endpoints['Name'] == e]
        aws_row = aws_endpoints[aws_endpoints['Name'] == e]
        
        ls_latencies.append(ls_row['Average Response Time'].values[0] if len(ls_row) > 0 else 0)
        aws_latencies.append(aws_row['Average Response Time'].values[0] if len(aws_row) > 0 else 0)
    
    bars1 = ax.bar([i - width/2 for i in x], ls_latencies, width, label='LocalStack', color='#2ecc71')
    bars2 = ax.bar([i + width/2 for i in x], aws_latencies, width, label='AWS', color='#3498db')
    
    ax.set_xlabel('Endpoint', fontsize=12)
    ax.set_ylabel('Average Response Time (ms)', fontsize=12)
    ax.set_title('Latency Comparison: LocalStack vs AWS', fontsize=14, fontweight='bold')
    ax.set_xticks(x)
    ax.set_xticklabels([e.replace('POST ', '').replace('GET ', '') for e in endpoints], rotation=45, ha='right')
    ax.legend()
    ax.grid(axis='y', alpha=0.3)
    
    # Add value labels
    for bar in bars1:
        height = bar.get_height()
        if height > 0:
            ax.annotate(f'{height:.0f}',
                        xy=(bar.get_x() + bar.get_width() / 2, height),
                        xytext=(0, 3), textcoords="offset points",
                        ha='center', va='bottom', fontsize=8)
    for bar in bars2:
        height = bar.get_height()
        if height > 0:
            ax.annotate(f'{height:.0f}',
                        xy=(bar.get_x() + bar.get_width() / 2, height),
                        xytext=(0, 3), textcoords="offset points",
                        ha='center', va='bottom', fontsize=8)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'latency_comparison.png', dpi=150)
    plt.close()
    print(f"  ✅ Saved: latency_comparison.png")


def plot_throughput_comparison(ls_stats: pd.DataFrame, aws_stats: pd.DataFrame, output_dir: Path):
    """Create throughput comparison chart."""
    fig, ax = plt.subplots(figsize=(8, 6))
    
    ls_agg = get_aggregated_row(ls_stats)
    aws_agg = get_aggregated_row(aws_stats)
    
    environments = ['LocalStack', 'AWS']
    rps = [ls_agg.get('Requests/s', 0), aws_agg.get('Requests/s', 0)]
    colors = ['#2ecc71', '#3498db']
    
    bars = ax.bar(environments, rps, color=colors, width=0.5)
    
    ax.set_ylabel('Requests per Second (RPS)', fontsize=12)
    ax.set_title('Throughput Comparison: LocalStack vs AWS', fontsize=14, fontweight='bold')
    ax.grid(axis='y', alpha=0.3)
    
    for bar, val in zip(bars, rps):
        ax.annotate(f'{val:.1f}',
                    xy=(bar.get_x() + bar.get_width() / 2, bar.get_height()),
                    xytext=(0, 3), textcoords="offset points",
                    ha='center', va='bottom', fontsize=14, fontweight='bold')
    
    plt.tight_layout()
    plt.savefig(output_dir / 'throughput_comparison.png', dpi=150)
    plt.close()
    print(f"  ✅ Saved: throughput_comparison.png")


def plot_percentile_comparison(ls_stats: pd.DataFrame, aws_stats: pd.DataFrame, output_dir: Path):
    """Create response time percentile comparison."""
    fig, ax = plt.subplots(figsize=(10, 6))
    
    ls_agg = get_aggregated_row(ls_stats)
    aws_agg = get_aggregated_row(aws_stats)
    
    percentiles = ['50%', '75%', '95%', '99%']
    percentile_labels = ['P50', 'P75', 'P95', 'P99']
    x = range(len(percentiles))
    width = 0.35
    
    ls_vals = [ls_agg.get(p, 0) for p in percentiles]
    aws_vals = [aws_agg.get(p, 0) for p in percentiles]
    
    bars1 = ax.bar([i - width/2 for i in x], ls_vals, width, label='LocalStack', color='#2ecc71')
    bars2 = ax.bar([i + width/2 for i in x], aws_vals, width, label='AWS', color='#3498db')
    
    ax.set_xlabel('Percentile', fontsize=12)
    ax.set_ylabel('Response Time (ms)', fontsize=12)
    ax.set_title('Response Time Percentiles: LocalStack vs AWS', fontsize=14, fontweight='bold')
    ax.set_xticks(x)
    ax.set_xticklabels(percentile_labels)
    ax.legend()
    ax.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'percentile_comparison.png', dpi=150)
    plt.close()
    print(f"  ✅ Saved: percentile_comparison.png")


def plot_failure_comparison(ls_stats: pd.DataFrame, aws_stats: pd.DataFrame, output_dir: Path):
    """Create failure rate comparison."""
    fig, ax = plt.subplots(figsize=(10, 6))
    
    ls_endpoints = ls_stats[ls_stats['Name'] != 'Aggregated'].copy()
    aws_endpoints = aws_stats[aws_stats['Name'] != 'Aggregated'].copy()
    
    ls_endpoints['Failure Rate'] = ls_endpoints['Failure Count'] / ls_endpoints['Request Count'].replace(0, 1) * 100
    aws_endpoints['Failure Rate'] = aws_endpoints['Failure Count'] / aws_endpoints['Request Count'].replace(0, 1) * 100
    
    endpoints = ls_endpoints['Name'].unique()
    x = range(len(endpoints))
    width = 0.35
    
    ls_rates = []
    aws_rates = []
    
    for e in endpoints:
        ls_row = ls_endpoints[ls_endpoints['Name'] == e]
        aws_row = aws_endpoints[aws_endpoints['Name'] == e]
        
        ls_rates.append(ls_row['Failure Rate'].values[0] if len(ls_row) > 0 else 0)
        aws_rates.append(aws_row['Failure Rate'].values[0] if len(aws_row) > 0 else 0)
    
    bars1 = ax.bar([i - width/2 for i in x], ls_rates, width, label='LocalStack', color='#2ecc71')
    bars2 = ax.bar([i + width/2 for i in x], aws_rates, width, label='AWS', color='#3498db')
    
    ax.set_xlabel('Endpoint', fontsize=12)
    ax.set_ylabel('Failure Rate (%)', fontsize=12)
    ax.set_title('Failure Rate Comparison: LocalStack vs AWS', fontsize=14, fontweight='bold')
    ax.set_xticks(x)
    ax.set_xticklabels([e.replace('POST ', '').replace('GET ', '') for e in endpoints], rotation=45, ha='right')
    ax.legend()
    ax.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'failure_comparison.png', dpi=150)
    plt.close()
    print(f"  ✅ Saved: failure_comparison.png")


def plot_timeline(ls_history: pd.DataFrame, aws_history: pd.DataFrame, output_dir: Path):
    """Create RPS over time comparison."""
    if ls_history is None or aws_history is None:
        print("  ⚠️  Skipping timeline (history data not available)")
        return
    
    fig, axes = plt.subplots(2, 1, figsize=(12, 8))
    
    # Normalize to elapsed time
    if 'Timestamp' in ls_history.columns:
        ls_history = ls_history.copy()
        ls_history['Elapsed'] = (ls_history['Timestamp'] - ls_history['Timestamp'].min()).dt.total_seconds()
    
    if 'Timestamp' in aws_history.columns:
        aws_history = aws_history.copy()
        aws_history['Elapsed'] = (aws_history['Timestamp'] - aws_history['Timestamp'].min()).dt.total_seconds()
    
    # LocalStack
    if 'Requests/s' in ls_history.columns and 'Elapsed' in ls_history.columns:
        axes[0].plot(ls_history['Elapsed'], ls_history['Requests/s'], color='#2ecc71', linewidth=1.5)
        axes[0].fill_between(ls_history['Elapsed'], ls_history['Requests/s'], alpha=0.3, color='#2ecc71')
    axes[0].set_ylabel('Requests/s', fontsize=11)
    axes[0].set_title('LocalStack - Throughput Over Time', fontsize=12, fontweight='bold')
    axes[0].grid(alpha=0.3)
    
    # AWS
    if 'Requests/s' in aws_history.columns and 'Elapsed' in aws_history.columns:
        axes[1].plot(aws_history['Elapsed'], aws_history['Requests/s'], color='#3498db', linewidth=1.5)
        axes[1].fill_between(aws_history['Elapsed'], aws_history['Requests/s'], alpha=0.3, color='#3498db')
    axes[1].set_xlabel('Time (seconds)', fontsize=11)
    axes[1].set_ylabel('Requests/s', fontsize=11)
    axes[1].set_title('AWS - Throughput Over Time', fontsize=12, fontweight='bold')
    axes[1].grid(alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'timeline_comparison.png', dpi=150)
    plt.close()
    print(f"  ✅ Saved: timeline_comparison.png")


def generate_report(summary: pd.DataFrame, output_dir: Path):
    """Generate markdown report."""
    report = f"""# LocalStack vs AWS Deployment Comparison Report

**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## Executive Summary

This report compares the performance of a microservices architecture deployed on:
1. **LocalStack** - Local AWS emulation
2. **AWS** - Real cloud infrastructure (Learner Lab)

## Performance Comparison

{summary.to_markdown(index=False)}

## Key Findings

### 1. Latency
- **LocalStack** shows lower latency due to local network (no internet round-trip)
- **AWS** latency includes real network overhead, ALB processing, and ECS scheduling

![Latency Comparison](latency_comparison.png)

### 2. Throughput
- Compare RPS (Requests Per Second) between environments
- LocalStack is limited by local machine resources
- AWS can scale with infrastructure

![Throughput Comparison](throughput_comparison.png)

### 3. Response Time Distribution

![Percentile Comparison](percentile_comparison.png)

### 4. Failure Rates
- Product endpoint expected ~25% failure (50% traffic to bad service × 50% failure rate)
- AWS ALB may route away from unhealthy instances (Automatic Target Weights)
- LocalStack/Nginx uses simple round-robin

![Failure Comparison](failure_comparison.png)

### 5. Performance Over Time

![Timeline Comparison](timeline_comparison.png)

## Recommendations

| Use Case | Recommended Environment | Reason |
|----------|------------------------|--------|
| Rapid development | LocalStack | Fast iteration, no cost |
| Unit/Integration tests | LocalStack | Quick feedback loop |
| Load testing | AWS | Realistic performance data |
| CI/CD pipeline | LocalStack | Fast, deterministic |
| Pre-production validation | AWS | Real infrastructure behavior |

## Limitations Observed

### LocalStack Limitations
1. ECS Docker Mode networking issues (required manual container startup)
2. ALB routing required Host header workaround
3. Some AWS API behaviors differ from real AWS

### AWS Learner Lab Limitations
1. Limited credits/resources
2. Session timeouts
3. Some services restricted

## Conclusion

LocalStack is valuable for development and testing, but real AWS deployment is essential for:
- Accurate performance benchmarking
- Testing ALB health check behavior
- Validating production-like scenarios
"""
    
    with open(output_dir / 'comparison_report.md', 'w') as f:
        f.write(report)
    print(f"  ✅ Saved: comparison_report.md")


def main():
    parser = argparse.ArgumentParser(description='Compare LocalStack vs AWS results')
    parser.add_argument('--localstack', type=Path, default=LOCALSTACK_DIR, help='LocalStack results directory')
    parser.add_argument('--aws', type=Path, default=AWS_DIR, help='AWS results directory')
    parser.add_argument('--output', type=Path, default=OUTPUT_DIR, help='Output directory')
    args = parser.parse_args()
    
    print("\n" + "=" * 60)
    print("  LOCALSTACK vs AWS COMPARISON")
    print("=" * 60 + "\n")
    
    # Find CSV files
    ls_csv = find_latest_csv(args.localstack)
    aws_csv = find_latest_csv(args.aws)
    
    if not ls_csv:
        print(f"❌ LocalStack results not found in {args.localstack}")
        print("   Run LocalStack test first!")
        sys.exit(1)
    
    if not aws_csv:
        print(f"❌ AWS results not found in {args.aws}")
        print("   Run AWS test first!")
        sys.exit(1)
    
    print(f"📁 LocalStack: {ls_csv}")
    print(f"📁 AWS:        {aws_csv}")
    
    # Load data
    print("\n📥 Loading data...")
    ls_stats = load_stats(ls_csv)
    aws_stats = load_stats(aws_csv)
    ls_history = load_history(args.localstack)
    aws_history = load_history(args.aws)
    
    if ls_stats is None or aws_stats is None:
        print("❌ Failed to load stats files")
        sys.exit(1)
    
    print(f"   LocalStack: {len(ls_stats)} rows")
    print(f"   AWS: {len(aws_stats)} rows")
    
    # Create output directory
    args.output.mkdir(parents=True, exist_ok=True)
    
    # Generate summary
    print("\n📊 Creating summary...")
    summary = create_summary(ls_stats, aws_stats)
    print("\n" + summary.to_string(index=False))
    
    # Save summary CSV
    summary.to_csv(args.output / 'summary.csv', index=False)
    print(f"\n  ✅ Saved: summary.csv")
    
    # Generate charts
    print("\n🎨 Generating charts...")
    plot_latency_comparison(ls_stats, aws_stats, args.output)
    plot_throughput_comparison(ls_stats, aws_stats, args.output)
    plot_percentile_comparison(ls_stats, aws_stats, args.output)
    plot_failure_comparison(ls_stats, aws_stats, args.output)
    plot_timeline(ls_history, aws_history, args.output)
    
    # Generate report
    print("\n📝 Generating report...")
    generate_report(summary, args.output)
    
    print("\n" + "=" * 60)
    print(f"  ✅ Comparison complete!")
    print(f"  📁 Results: {args.output}")
    print("=" * 60 + "\n")


if __name__ == '__main__':
    main()