# 🚀 GitHub Actions Setup Guide

## ⚡ Quick Setup (5 minutes)

### Step 1: Add Gemini API Key

1. **Get API Key**
   - Visit: https://makersuite.google.com/app/apikey
   - Click "Create API Key"
   - Copy the key

2. **Add to GitHub**
   - Go to your repository
   - Click: Settings → Secrets and variables → Actions
   - Click: "New repository secret"
   - Name: `GEMINI_API_KEY`
   - Value: Paste your API key
   - Click: "Add secret"

### Step 2: Enable Workflows

1. Go to: Actions tab
2. If prompted, click "I understand my workflows, go ahead and enable them"
3. Done! Workflows are now active

### Step 3: Test Setup

**Option A: Create a Test PR**
```bash
# Create a test branch
git checkout -b test-workflows

# Make a small change
echo "// Test" >> lib/main.dart

# Commit and push
git add .
git commit -m "test: workflows setup"
git push origin test-workflows

# Create PR on GitHub
# Watch workflows run automatically
```

**Option B: Manual Trigger**
1. Go to: Actions → AI Code Review
2. Click: "Run workflow"
3. Select: Review scope = "changed"
4. Click: "Run workflow"
5. Wait for completion
6. Download artifact to see report

---

## 📋 What You Get

### Automatic on Every PR:
✅ **PR Quality Check** (15 min)
- Static analysis
- Tests
- Coverage
- Quick AI review
- Quality report comment

✅ **AI Code Review** (20 min)
- Detailed review of changed files
- Architecture validation
- SOLID principles check
- Downloadable report

### Scheduled (Automatic):
✅ **Daily Review** (Mon-Fri, 9 AM UTC)
- Reviews yesterday's changes
- Quick feedback

✅ **Weekly Review** (Monday, 8 AM UTC)
- Full layer-by-layer review
- Architecture deep dive

### On-Demand (Manual):
✅ **Security Audit**
- Full security scan
- Vulnerability detection

✅ **Performance Review**
- Performance analysis
- Bottleneck identification

---

## 🎯 Usage Scenarios

### Scenario 1: Daily Development

```
Morning:
1. Check daily review report (if available)
2. Review findings from yesterday

During Development:
1. Write code
2. Commit changes
3. Create PR
4. Wait for quality check
5. Review AI feedback
6. Fix issues
7. Push updates
8. Merge when green

End of Day:
1. Check if all PRs passed quality gate
```

### Scenario 2: Before Release

```
1 Week Before:
1. Run security audit
2. Fix critical security issues
3. Run performance review
4. Optimize bottlenecks

3 Days Before:
1. Run full weekly review
2. Fix high priority issues
3. Update documentation

1 Day Before:
1. Final quality check
2. Verify all tests pass
3. Check coverage
4. Review recent changes
```

### Scenario 3: Refactoring

```
Planning:
1. Run review on target layer
2. Identify issues
3. Prioritize fixes
4. Create refactoring plan

Execution:
1. Create feature branch
2. Make changes
3. Create PR
4. Review AI feedback
5. Iterate until clean
6. Merge

Verification:
1. Run layer review again
2. Compare before/after
3. Document improvements
```

---

## 🔧 Customization

### Change Review Language

Edit workflow files:
```yaml
--language vi  # Vietnamese
--language ja  # Japanese
--language ko  # Korean
```

### Adjust Schedule

Edit `scheduled_code_review.yml`:
```yaml
schedule:
  - cron: '0 9 * * 1-5'  # Daily at 9 AM UTC
  - cron: '0 8 * * 1'    # Weekly Monday 8 AM UTC
```

### Modify Quality Gate

Edit `pr_quality_check.yml`:
```yaml
# Make coverage mandatory
if [ "$COVERAGE" -lt 70 ]; then
  exit 1  # Fail build
fi
```

### Add Notifications

Add to workflow:
```yaml
- name: Notify Team
  if: failure()
  run: |
    # Send Slack notification
    curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
      -d '{"text":"Code review found issues"}'
```

---

## 📊 Monitoring

### Check Workflow Status

**Dashboard**:
- Go to: Actions tab
- See all workflow runs
- Filter by status/workflow

**Badges**:
Add to README.md:
```markdown
![Quality](https://github.com/USER/REPO/workflows/PR%20Quality%20Check/badge.svg)
```

### Review Reports

**PR Comments**:
- Automatic quality report on every PR
- Summary of findings
- Links to detailed reports

**Artifacts**:
- Click workflow run
- Scroll to "Artifacts"
- Download reports
- Review in detail

### Track Metrics

**Weekly**:
- Number of issues found
- Issues by priority
- Coverage trends
- Quality scores

**Monthly**:
- Overall code quality trend
- Most common issues
- Improvement areas
- Team performance

---

## 🐛 Common Issues

### Issue: Workflow doesn't run

**Causes**:
- Workflows not enabled
- Branch not in trigger list
- Path filters exclude changes

**Solution**:
```yaml
# Check trigger configuration
on:
  pull_request:
    branches: [main, develop]  # Add your branch
    paths:
      - 'lib/**/*.dart'  # Adjust paths
```

### Issue: API key error

**Error**: "GEMINI_API_KEY not found"

**Solution**:
1. Verify secret name is exactly `GEMINI_API_KEY`
2. Check secret is in correct repository
3. Re-add secret if needed

### Issue: Timeout

**Error**: "Workflow timed out"

**Solution**:
```yaml
# Increase timeout
timeout-minutes: 60  # From 30
```

### Issue: No PR comment

**Causes**:
- GITHUB_TOKEN permissions
- Script error
- No report generated

**Solution**:
1. Check workflow logs
2. Verify report file exists
3. Check script for errors

---

## 🎓 Learning Resources

### Understanding Workflows
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [Workflow Syntax](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions)

### Code Review Tool
- [Tool README](../tools/code_review/TOOL_README.md)
- [Usage Guide](../tools/code_review/USAGE_GUIDE.md)

### Project Documentation
- [Architecture](../docs/01_ARCHITECTURE.md)
- [Testing Guide](../docs/06_TESTING.md)

---

## ✅ Verification Checklist

After setup, verify:

- [ ] GEMINI_API_KEY secret added
- [ ] Workflows enabled in Actions tab
- [ ] Test PR created and workflows ran
- [ ] Quality report commented on PR
- [ ] Artifacts downloadable
- [ ] Manual workflow trigger works
- [ ] Team notified about new workflows
- [ ] Documentation updated

---

## 🚀 Next Steps

1. **Week 1**: Monitor automatic reviews
2. **Week 2**: Run manual security audit
3. **Week 3**: Review weekly reports
4. **Week 4**: Analyze trends and adjust

---

## 💡 Tips

### For Developers
- Check PR comments before requesting review
- Fix issues before asking for human review
- Download detailed reports for learning

### For Team Leads
- Review weekly reports in team meetings
- Track quality metrics over time
- Adjust workflows based on team needs

### For DevOps
- Monitor workflow execution times
- Optimize for faster feedback
- Set up notifications for failures

---

## 🤝 Support

**Questions?**
- Check [Workflows README](workflows/README.md)
- Review [Tool Documentation](../tools/code_review/)
- Ask in team chat

**Issues?**
- Check workflow logs
- Review troubleshooting section
- Create issue with details

---

**Setup Complete! 🎉**

Your automated code review system is now active. Happy coding!
