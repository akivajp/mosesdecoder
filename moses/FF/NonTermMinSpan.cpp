#include <vector>
#include "NonTermMinSpan.h"
#include "moses/ScoreComponentCollection.h"
#include "moses/TargetPhrase.h"
#include "moses/StackVec.h"
#include "moses/ChartCellLabel.h"

using namespace std;

namespace Moses
{
NonTermMinSpan::NonTermMinSpan(const std::string &line)
  :StatelessFeatureFunction(2, line)
  ,m_minSpan(2)
{
  ReadParameters();
}

void NonTermMinSpan::EvaluateInIsolation(const Phrase &source
                                   , const TargetPhrase &targetPhrase
                                   , ScoreComponentCollection &scoreBreakdown
                                   , ScoreComponentCollection &estimatedFutureScore) const
{
  // dense scores
  vector<float> newScores(m_numScoreComponents);
  newScores[0] = 1.5;
  newScores[1] = 0.3;
  scoreBreakdown.PlusEquals(this, newScores);

  // sparse scores
  scoreBreakdown.PlusEquals(this, "sparse-name", 2.4);

}

void NonTermMinSpan::EvaluateWithSourceContext(const InputType &input
                                   , const InputPath &inputPath
                                   , const TargetPhrase &targetPhrase
                                   , const StackVec *stackVec
                                   , ScoreComponentCollection &scoreBreakdown
                                   , ScoreComponentCollection *estimatedFutureScore) const
{
	assert(stackVec);

	for (size_t ntInd = 0; ntInd < stackVec->size(); ++ntInd) {
		const ChartCellLabel &cell = *stackVec->at(ntInd);
		const WordsRange &range = cell.GetCoverage();

		if (range.GetNumWordsCovered() < m_minSpan) {
			  scoreBreakdown.PlusEquals(this, - std::numeric_limits<float>::infinity());
			  return;
		}
	}
}

void NonTermMinSpan::EvaluateWhenApplied(const Hypothesis& hypo,
                                   ScoreComponentCollection* accumulator) const
{}

void NonTermMinSpan::EvaluateWhenApplied(const ChartHypothesis &hypo,
                                        ScoreComponentCollection* accumulator) const
{}

void NonTermMinSpan::SetParameter(const std::string& key, const std::string& value)
{
  if (key == "min-span") {
	  m_minSpan = Scan<size_t>(value);
  } else {
    StatelessFeatureFunction::SetParameter(key, value);
  }
}

}
